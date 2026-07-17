'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(`${__dirname}/script.js`, 'utf8');

function createElement() {
    return {
        className: '',
        disabled: false,
        hidden: true,
        textContent: '',
        value: '',
        focused: false,
        focus() {
            this.focused = true;
        },
    };
}

function createHarness({
    configured = true,
    updateError = false,
    urlMode = 'implicit',
    verifyError = false,
} = {}) {
    const elements = {
        'reset-password-form': createElement(),
        password: createElement(),
        'confirm-password': createElement(),
        message: createElement(),
        'submit-button': createElement(),
    };
    const form = elements['reset-password-form'];
    const listeners = {};
    const windowListeners = {};
    const historyCalls = [];
    let authStateHandler;
    let timeoutHandler;
    let updateCalls = 0;
    let signOutCalls = 0;
    let verifyCalls = 0;

    form.addEventListener = (type, callback) => {
        listeners[type] = callback;
    };
    form.reset = () => {
        elements.password.value = '';
        elements['confirm-password'].value = '';
    };

    const auth = {
        onAuthStateChange(callback) {
            authStateHandler = callback;
        },
        async updateUser(payload) {
            updateCalls += 1;
            assert.equal(typeof payload.password, 'string');
            return { error: updateError ? { message: 'TEST_ONLY raw backend error' } : null };
        },
        async signOut() {
            signOutCalls += 1;
            return { error: null };
        },
        async verifyOtp(payload) {
            verifyCalls += 1;
            assert.equal(payload.token_hash, 'TOKEN_HASH_TEST_ONLY');
            assert.equal(payload.type, 'recovery');
            return verifyError
                ? { data: { session: null }, error: { message: 'TEST_ONLY raw verify error' } }
                : { data: { session: { access_token: 'TEST_ONLY' } }, error: null };
        },
    };

    const locations = {
        implicit: {
            hash: '#access_token=RECOVERY_MATERIAL_TEST_ONLY&refresh_token=TEST_ONLY&type=recovery',
            search: '',
        },
        tokenHash: {
            hash: '#token_hash=TOKEN_HASH_TEST_ONLY&type=recovery',
            search: '',
        },
        pkce: {
            hash: '',
            search: '?code=PKCE_CODE_TEST_ONLY',
        },
    };

    const window = {
        __RESET_PASSWORD_CONFIG__: configured
            ? {
                supabaseUrl: 'https://supabase.test.invalid',
                supabasePublishableKey: 'sb_publishable_TEST_ONLY_0000000000000000',
            }
            : undefined,
        supabase: configured ? { createClient: () => ({ auth }) } : undefined,
        location: {
            hash: locations[urlMode].hash,
            pathname: '/reset',
            search: locations[urlMode].search,
        },
        history: {
            replaceState(...args) {
                historyCalls.push(args);
                window.location.hash = '';
                window.location.search = '';
            },
        },
        setTimeout(callback) {
            timeoutHandler = callback;
            return 1;
        },
        addEventListener(type, callback) {
            windowListeners[type] = callback;
        },
    };

    vm.runInNewContext(source, {
        document: {
            title: 'TEST_ONLY',
            getElementById(id) {
                return elements[id];
            },
        },
        URLSearchParams,
        window,
    }, { filename: 'script.js' });

    return {
        elements,
        historyCalls,
        get updateCalls() { return updateCalls; },
        get signOutCalls() { return signOutCalls; },
        get verifyCalls() { return verifyCalls; },
        emitAuth(event, session) {
            authStateHandler(event, session);
        },
        expire() {
            timeoutHandler();
        },
        async submit() {
            await listeners.submit({ preventDefault() {} });
        },
        pagehide() {
            windowListeners.pagehide();
        },
        async flush() {
            await new Promise((resolve) => setImmediate(resolve));
        },
    };
}

async function main() {
    const invalid = createHarness({ configured: false });
    assert.equal(invalid.elements.password.disabled, true);
    assert.match(invalid.elements.message.textContent, /chưa được cấu hình đúng/);
    assert.equal(invalid.historyCalls.length, 1);

    const expired = createHarness();
    expired.expire();
    assert.equal(expired.elements.password.disabled, true);
    assert.match(expired.elements.message.textContent, /không hợp lệ hoặc đã hết hạn/);

    const pkce = createHarness({ urlMode: 'pkce' });
    assert.equal(pkce.elements.password.disabled, true);
    assert.match(pkce.elements.message.textContent, /không hợp lệ hoặc đã hết hạn/);
    assert.equal(pkce.historyCalls.length, 1);

    const tokenHash = createHarness({ urlMode: 'tokenHash' });
    await tokenHash.flush();
    assert.equal(tokenHash.verifyCalls, 1);
    assert.equal(tokenHash.elements.password.disabled, false);
    assert.equal(tokenHash.historyCalls.length, 1);

    const badTokenHash = createHarness({ urlMode: 'tokenHash', verifyError: true });
    await badTokenHash.flush();
    assert.equal(badTokenHash.verifyCalls, 1);
    assert.equal(badTokenHash.elements.password.disabled, true);
    assert.doesNotMatch(badTokenHash.elements.message.textContent, /raw verify error/);

    const success = createHarness();
    success.emitAuth('PASSWORD_RECOVERY', { access_token: 'TEST_ONLY' });
    assert.equal(success.elements.password.disabled, false);
    assert.equal(success.elements.password.focused, true);
    assert.equal(success.historyCalls.length, 1);
    success.elements.password.value = 'TEST_ONLY-password';
    success.elements['confirm-password'].value = 'TEST_ONLY-password';
    await success.submit();
    assert.equal(success.updateCalls, 1);
    assert.equal(success.signOutCalls, 1);
    assert.equal(success.elements.password.value, '');
    assert.equal(success.elements['confirm-password'].value, '');
    assert.equal(success.elements.password.disabled, true);
    assert.match(success.elements.message.textContent, /đã được cập nhật/);
    await success.submit();
    assert.equal(success.updateCalls, 1, 'reused form must not update password twice');

    const failed = createHarness({ updateError: true });
    failed.emitAuth('PASSWORD_RECOVERY', { access_token: 'TEST_ONLY' });
    failed.elements.password.value = 'TEST_ONLY-password';
    failed.elements['confirm-password'].value = 'TEST_ONLY-password';
    await failed.submit();
    assert.equal(failed.updateCalls, 1);
    assert.equal(failed.elements['submit-button'].disabled, false);
    assert.doesNotMatch(failed.elements.message.textContent, /raw backend error/);
    failed.pagehide();
    assert.equal(failed.elements.password.value, '');

    const slow = createHarness();
    slow.expire();
    slow.emitAuth('PASSWORD_RECOVERY', { access_token: 'TEST_ONLY' });
    assert.equal(slow.elements.password.disabled, false);

    process.stdout.write('JavaScript recovery harness pass.\n');
}

main().catch((error) => {
    process.stderr.write(`${error.stack}\n`);
    process.exitCode = 1;
});
