(() => {
    'use strict';

    const form = document.getElementById('reset-password-form');
    const passwordInput = document.getElementById('password');
    const confirmPasswordInput = document.getElementById('confirm-password');
    const messageElement = document.getElementById('message');
    const submitButton = document.getElementById('submit-button');

    let recoverySessionReady = false;
    let updateSucceeded = false;

    function showMessage(message, type = 'error') {
        messageElement.textContent = message;
        messageElement.className = `message ${type}`;
        messageElement.hidden = false;
    }

    function hideMessage() {
        messageElement.hidden = true;
        messageElement.textContent = '';
        messageElement.className = 'message';
    }

    function setFormEnabled(enabled) {
        passwordInput.disabled = !enabled;
        confirmPasswordInput.disabled = !enabled;
        submitButton.disabled = !enabled;
    }

    function setLoading(loading) {
        submitButton.disabled = loading;
        submitButton.textContent = loading ? 'Đang cập nhật…' : 'Cập nhật mật khẩu';
    }

    function clearSensitiveUrl() {
        if (window.location.search || window.location.hash) {
            window.history.replaceState(null, document.title, window.location.pathname);
        }
    }

    function failClosed(message) {
        recoverySessionReady = false;
        setFormEnabled(false);
        showMessage(message);
    }

    function activateRecoverySession() {
        recoverySessionReady = true;
        clearSensitiveUrl();
        hideMessage();
        setFormEnabled(true);
        passwordInput.focus();
    }

    const queryParameters = new URLSearchParams(window.location.search);
    const fragmentParameters = new URLSearchParams(window.location.hash.replace(/^#/, ''));
    const recoveryType = fragmentParameters.get('type') || queryParameters.get('type');
    const recoveryTokenHash = fragmentParameters.get('token_hash') || queryParameters.get('token_hash');
    const hasImplicitRecoverySession = recoveryType === 'recovery'
        && fragmentParameters.has('access_token')
        && fragmentParameters.has('refresh_token');
    const hasTokenHashRecovery = recoveryType === 'recovery' && Boolean(recoveryTokenHash);
    const hasUnsupportedPkceCode = queryParameters.has('code');

    const config = window.__RESET_PASSWORD_CONFIG__;
    if (!config
        || typeof config.supabaseUrl !== 'string'
        || typeof config.supabasePublishableKey !== 'string'
        || !config.supabaseUrl
        || !config.supabasePublishableKey
        || !window.supabase) {
        clearSensitiveUrl();
        failClosed('Trang khôi phục chưa được cấu hình đúng. Vui lòng liên hệ hỗ trợ.');
        return;
    }

    if (hasUnsupportedPkceCode || (!hasImplicitRecoverySession && !hasTokenHashRecovery)) {
        clearSensitiveUrl();
        failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
        return;
    }

    let supabaseClient;
    try {
        supabaseClient = window.supabase.createClient(
            config.supabaseUrl,
            config.supabasePublishableKey,
            {
                auth: {
                    autoRefreshToken: false,
                    detectSessionInUrl: hasImplicitRecoverySession,
                    flowType: 'implicit',
                    persistSession: false,
                },
            },
        );
    } catch (_) {
        clearSensitiveUrl();
        failClosed('Trang khôi phục chưa được cấu hình đúng. Vui lòng liên hệ hỗ trợ.');
        return;
    }

    supabaseClient.auth.onAuthStateChange((event, currentSession) => {
        if (event === 'PASSWORD_RECOVERY' && currentSession) {
            activateRecoverySession();
            return;
        }

        if (event === 'SIGNED_OUT' && !updateSucceeded) {
            clearSensitiveUrl();
            failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
        }
    });

    if (hasTokenHashRecovery) {
        clearSensitiveUrl();
        void (async () => {
            try {
                const { data, error } = await supabaseClient.auth.verifyOtp({
                    token_hash: recoveryTokenHash,
                    type: 'recovery',
                });
                if (error || !data.session) {
                    failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
                    return;
                }
                activateRecoverySession();
            } catch (_) {
                failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
            }
        })();
    } else {
        window.setTimeout(() => {
            if (!recoverySessionReady && !updateSucceeded) {
                clearSensitiveUrl();
                failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
            }
        }, 15000);
    }

    form.addEventListener('submit', async (event) => {
        event.preventDefault();
        hideMessage();

        if (!recoverySessionReady) {
            failClosed('Liên kết không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu email khôi phục mới.');
            return;
        }

        const password = passwordInput.value;
        const confirmation = confirmPasswordInput.value;

        if (password.length < 6) {
            showMessage('Mật khẩu phải có ít nhất 6 ký tự.');
            return;
        }

        if (password !== confirmation) {
            showMessage('Hai mật khẩu không khớp.');
            return;
        }

        setLoading(true);

        try {
            const { error } = await supabaseClient.auth.updateUser({ password });
            if (error) {
                showMessage('Không thể cập nhật mật khẩu. Liên kết có thể đã hết hạn; vui lòng thử lại bằng email khôi phục mới.');
                setLoading(false);
                return;
            }

            updateSucceeded = true;
            recoverySessionReady = false;
            form.reset();
            passwordInput.disabled = true;
            confirmPasswordInput.disabled = true;
            submitButton.disabled = true;
            submitButton.textContent = 'Đã cập nhật mật khẩu';
            clearSensitiveUrl();
            showMessage('Mật khẩu đã được cập nhật. Bạn có thể đóng trang này và đăng nhập lại.', 'success');
            await supabaseClient.auth.signOut({ scope: 'local' }).catch(() => {});
        } catch (_) {
            showMessage('Không thể cập nhật mật khẩu. Vui lòng yêu cầu email khôi phục mới và thử lại.');
            setLoading(false);
        } finally {
            passwordInput.value = '';
            confirmPasswordInput.value = '';
        }
    });

    window.addEventListener('pagehide', () => {
        passwordInput.value = '';
        confirmPasswordInput.value = '';
    });
})();
