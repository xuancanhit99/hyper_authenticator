// --- Configuration ---
// Get environment variables from window.ENV object created by env-config.js (injected by Dockerfile)
const SUPABASE_URL = window.ENV?.SUPABASE_URL;
const SUPABASE_ANON_KEY = window.ENV?.SUPABASE_ANON_KEY;

// Basic check if variables were loaded
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.error("ERROR: Supabase URL or Anon Key not found. Check environment variables and env-config.js injection.");
    // Optionally display an error message to the user on the page
    // showMessage("Configuration error. Unable to initialize Supabase.");
}

// --- Initialize Supabase Client ---
// Ensure you are using the correct import based on the CDN version
// For v2: supabase.createClient
// Check the Supabase JS docs if you use a different version
const { createClient } = supabase;
const _supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

console.log('Supabase client initialized');

// --- DOM Elements ---
const form = document.getElementById('reset-password-form');
const passwordInput = document.getElementById('password');
const confirmPasswordInput = document.getElementById('confirm-password');
const messageElement = document.getElementById('message');
const submitButton = document.getElementById('submit-button');

let session = null; // To store the session info after handling the redirect

// --- Functions ---
function showMessage(message, type = 'error') {
    messageElement.textContent = message;
    messageElement.className = `message ${type}`; // Apply 'success' or 'error' class
    messageElement.style.display = 'block';
}

function hideMessage() {
    messageElement.style.display = 'none';
    messageElement.textContent = '';
    messageElement.className = 'message';
}

function setLoading(isLoading) {
    submitButton.disabled = isLoading;
    submitButton.textContent = isLoading ? 'Updating...' : 'Update Password';
}

// --- Event Listeners ---

// Handle form submission
form.addEventListener('submit', async (event) => {
    event.preventDefault(); // Prevent default form submission
    hideMessage();
    setLoading(true);

    const password = passwordInput.value;
    const confirmPassword = confirmPasswordInput.value;

    if (password.length < 6) {
        showMessage('Password must be at least 6 characters long.');
        setLoading(false);
        return;
    }

    if (password !== confirmPassword) {
        showMessage('Passwords do not match.');
        setLoading(false);
        return;
    }

    // Check if we have a valid session (user should be authenticated via the link)
    if (!session) {
         // This might happen if the user navigates directly without the token,
         // or if the token handling failed.
        showMessage('Invalid session or expired link. Please request a new password reset link.');
        console.error("Attempted password update without a valid session.");
        setLoading(false);
        return;
    }

    try {
        // Update the user's password
        const { data, error } = await _supabase.auth.updateUser({ password: password });

        if (error) {
            console.error('Error updating password:', error);
            showMessage(`Error: ${error.message}`);
        } else {
            console.log('Password updated successfully:', data);
            showMessage('Password updated successfully! You can now close this page and log in with your new password.', 'success');
            // Optionally disable the form after success
            form.reset();
            passwordInput.disabled = true;
            confirmPasswordInput.disabled = true;
            submitButton.disabled = true;
            submitButton.textContent = 'Password Updated';
        }
    } catch (err) {
        console.error('Unexpected error during password update:', err);
        showMessage('An unexpected error occurred. Please try again.');
    } finally {
        // Only set loading to false if there was an error and we want the user to retry
        // If successful, the button remains disabled.
        if (messageElement.classList.contains('error')) {
             setLoading(false);
        }
    }
});

// Handle Auth State Changes (including redirect from email link)
_supabase.auth.onAuthStateChange((event, newSession) => {
    console.log('Auth State Change Event:', event, 'Session:', newSession);
    session = newSession; // Store the latest session

    if (event === 'PASSWORD_RECOVERY') {
        // This event fires after the user clicks the link and Supabase processes the token in the URL fragment.
        // The user is now temporarily authenticated in this browser session.
        console.log('Password recovery event detected. User is ready to set a new password.');
        hideMessage(); // Hide any previous messages
        // Enable the form if it was disabled
        passwordInput.disabled = false;
        confirmPasswordInput.disabled = false;
        submitButton.disabled = false;
    } else if (event === 'SIGNED_IN' && session) {
         console.log('User is signed in (might be from recovery link).');
         // Potentially redundant with PASSWORD_RECOVERY but good to log
    } else if (event === 'USER_UPDATED') {
        console.log('User data updated (likely password).');
    } else if (!session) {
        // If there's no session after initial load or an event, the link might be invalid/expired
        // or the user accessed the page directly.
        console.warn('No active session found.');
        // Consider showing a message only if the URL seems to have had a token initially
        if (window.location.hash.includes('access_token')) {
             showMessage('Link may be invalid or expired. Please request a new password reset link.');
        } else {
             showMessage('Please use the password reset link sent to your email.');
        }
        // Disable the form as the user isn't authenticated for password update
        passwordInput.disabled = true;
        confirmPasswordInput.disabled = true;
        submitButton.disabled = true;
    }
});

// Initial check in case the page loads and the event fires quickly
(async () => {
    const { data } = await _supabase.auth.getSession();
    session = data.session;
    if (!session && window.location.hash.includes('access_token')) {
        console.log("Initial load detected hash fragment, waiting for onAuthStateChange...");
        // onAuthStateChange should handle this soon
    } else if (!session) {
         console.log("Initial load: No session found and no token in URL.");
         showMessage('Please use the password reset link sent to your email.');
         passwordInput.disabled = true;
         confirmPasswordInput.disabled = true;
         submitButton.disabled = true;
    } else {
        console.log("Initial load: Session found.", session);
        // User might already be logged in somehow, but PASSWORD_RECOVERY event is key
    }
})();