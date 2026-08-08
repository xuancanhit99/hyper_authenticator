// The worker intentionally owns no TOTP data and no second-by-second timer.
// Chrome may suspend an MV3 worker at any time; the visible Flutter side panel
// renders countdowns and owns foreground sync.
chrome.runtime.onInstalled.addListener(() => {
  chrome.sidePanel
    .setPanelBehavior({ openPanelOnActionClick: true })
    .catch(() => undefined);
});
