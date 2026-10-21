// Only the isolated Chrome process's own loopback debugging endpoint is trusted.
export function chromeDebugEndpoint(rawUrl, port) {
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('Invalid isolated Chrome debugging port');
  }
  const url = new URL(rawUrl);
  if (url.protocol !== 'ws:' || url.hostname !== '127.0.0.1' ||
      url.port !== String(port) || url.username || url.password ||
      url.search || url.hash || !/^\/devtools\/page\/[a-zA-Z0-9-]+$/.test(url.pathname)) {
    throw new Error('Unexpected isolated Chrome debugging endpoint');
  }
  return url.href;
}
