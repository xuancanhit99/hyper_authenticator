const debugOrigin = process.argv[2];
const expectedPageUrl = process.argv[3];

if (!debugOrigin || !expectedPageUrl) {
  throw new Error('Thiếu Chrome DevTools endpoint hoặc app URL.');
}

const overallDeadline = Date.now() + 45_000;
const pending = new Map();
let nextId = 1;
let closing = false;

function assertWithinDeadline(context) {
  if (Date.now() >= overallDeadline) {
    throw new Error(`Web runtime probe quá hạn khi ${context}.`);
  }
}

const delay = async (milliseconds) => {
  assertWithinDeadline('chờ browser runtime');
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
};

async function fetchJson(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 1_000);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return null;
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function findPageTarget() {
  while (Date.now() < overallDeadline) {
    try {
      const targets = await fetchJson(`${debugOrigin}/json/list`);
      const page = Array.isArray(targets)
        ? targets.find(
            (target) =>
              target.type === 'page' &&
              typeof target.webSocketDebuggerUrl === 'string' &&
              (target.url === expectedPageUrl ||
                target.url.startsWith(`${expectedPageUrl}#`)),
          )
        : null;
      if (page) return page;
    } catch (_) {
      // Chrome may still be starting. Retry without exposing response data.
    }
    await delay(250);
  }
  throw new Error('Chrome DevTools không có đúng app page target sẵn sàng.');
}

const target = await findPageTarget();
const socket = new WebSocket(target.webSocketDebuggerUrl);

function rejectPending(message) {
  for (const [id, request] of pending) {
    clearTimeout(request.timer);
    request.reject(new Error(message));
    pending.delete(id);
  }
}

socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (!message.id || !pending.has(message.id)) return;
  const request = pending.get(message.id);
  pending.delete(message.id);
  clearTimeout(request.timer);
  if (message.error) {
    request.reject(
      new Error(`Chrome DevTools command lỗi: ${message.error.code}`),
    );
  } else {
    request.resolve(message.result);
  }
};

socket.onclose = () => {
  if (!closing) rejectPending('Chrome DevTools đóng kết nối ngoài dự kiến.');
};
socket.onerror = () => {
  rejectPending('Chrome DevTools gặp lỗi kết nối.');
};

await new Promise((resolve, reject) => {
  const timer = setTimeout(
    () => reject(new Error('Kết nối Chrome DevTools quá hạn.')),
    5_000,
  );
  socket.onopen = () => {
    clearTimeout(timer);
    resolve();
  };
  socket.onerror = () => {
    clearTimeout(timer);
    reject(new Error('Không kết nối được Chrome DevTools.'));
  };
});
socket.onerror = () => {
  rejectPending('Chrome DevTools gặp lỗi kết nối.');
};

function command(method, params = {}) {
  assertWithinDeadline(`gọi ${method}`);
  const id = nextId;
  nextId += 1;
  return new Promise((resolve, reject) => {
    const timeoutMs = Math.max(
      1,
      Math.min(5_000, overallDeadline - Date.now()),
    );
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`Chrome DevTools command quá hạn: ${method}.`));
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    try {
      socket.send(JSON.stringify({ id, method, params }));
    } catch (_) {
      clearTimeout(timer);
      pending.delete(id);
      reject(new Error(`Không gửi được Chrome DevTools command: ${method}.`));
    }
  });
}

async function evaluate(expression) {
  const response = await command('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  if (response.exceptionDetails) {
    throw new Error('JavaScript probe lỗi trong browser runtime.');
  }
  return response.result?.value;
}

await command('Runtime.enable');
await command('Page.enable');
await command('Accessibility.enable');

let glassPaneReady = false;
while (Date.now() < overallDeadline) {
  glassPaneReady =
    (await evaluate("document.querySelector('flt-glass-pane') !== null")) ===
    true;
  if (glassPaneReady) break;
  await delay(250);
}
if (!glassPaneReady) {
  throw new Error('Flutter Web engine không mount flt-glass-pane.');
}

let semanticsEnabled = false;
while (Date.now() < overallDeadline) {
  semanticsEnabled =
    (await evaluate(`(() => {
      const placeholder = document.querySelector('flt-semantics-placeholder');
      if (!placeholder) return false;
      placeholder.click();
      return true;
    })()`)) === true;
  if (semanticsEnabled) break;
  await delay(250);
}
if (!semanticsEnabled) {
  throw new Error('Flutter Web semantics placeholder không sẵn sàng.');
}

const startupFailure =
  'Không thể khởi động ứng dụng. Hãy kiểm tra cấu hình và thử lại.';
let shellReady = false;
while (Date.now() < overallDeadline) {
  const semanticsText = await evaluate(`(() => {
    const host = document.querySelector('flt-semantics-host');
    if (!host) return '';
    return Array.from(host.querySelectorAll('*'))
      .map((node) => [
        node.getAttribute('aria-label') || '',
        node.textContent || ''
      ].join(' '))
      .join('\\n');
  })()`);
  const accessibilityTree = await command('Accessibility.getFullAXTree');
  const accessibilityText = (accessibilityTree.nodes ?? [])
    .map((node) => node.name?.value)
    .filter((value) => typeof value === 'string')
    .join('\n');
  const observedText = `${semanticsText ?? ''}\n${accessibilityText}`;
  if (observedText.includes(startupFailure)) {
    throw new Error('Release artifact đang hiển thị StartupFailureApp.');
  }
  if (
    observedText.includes('Mã xác thực') &&
    observedText.includes('Tài khoản')
  ) {
    shellReady = true;
    break;
  }
  await delay(250);
}

closing = true;
socket.close();

if (!shellReady) {
  throw new Error('Flutter Web không render shell local-vault đã cấu hình.');
}

process.stdout.write(
  'Flutter Web runtime pass: engine mount, semantics và local-vault shell sẵn sàng.\n',
);
