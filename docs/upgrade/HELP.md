# Upgrade candidate help

## A device is missing

Open **Fix Connection** or **More → Connection Doctor**. The Doctor checks the Mac's current network path, receiving state and discovered-recipient count. It cannot inspect the phone's settings or prove a router permits peer connections. Open Quick Share on the phone, enable visibility there, and confirm both devices have a reachable local network. A usable internet connection alone is not proof of device reachability.

For supported Android-generated QR pairing, choose **Use QR** and review camera permission. Mac-generated sending QR remains available after choosing files in Send. QR does not remove network requirements. For a cable workflow, unlock Android, select File transfer mode and open USB. USB starts a separate operation; it does not resume a partial wireless payload.

## Favorites

Star a currently discovered recipient. Available favorites sort first; offline hints are shown without a send action. Remove hints in General Settings. Hints match the advertised name and broad type, not an authenticated identity. Always confirm the intended recipient and approve incoming transfers as usual.

## Text, links and screenshots

Send → Text or Link creates a private temporary UTF-8 file. A web link must use HTTP/HTTPS without embedded credentials. The recipient receives a text file; native Quick Share text/link payload interoperability is not claimed. Paste reads the clipboard only when clicked.

Screenshot to Device captures a selected display only after user action and macOS permission, or accepts an explicitly chosen existing image. Review the preview, then choose a recipient. Images are scaled to at most 4,096 pixels per side. No background recording or clipboard monitoring is added. Capture permission and real-device transmission need manual verification on the target Mac.

## USB folder tools

Filter searches only the already loaded folder; it is not a phone-wide search. Sort keeps folders first, with natural name ordering or descending known size. Select shown selects the visible listing; Clear selection removes it. Folder metadata may not include a meaningful byte size. A fatal MTP error closes the connection and resets stale connected state; reconnect before another operation. Partial downloads can remain in the destination—inspect them before retrying.

## Appearance and setup

Settings → Appearance offers System, Light, Dark, Vice Nights, Coastal Sunrise and Midnight Route. The theme applies to the app's own views; native permission/open/save dialogs remain macOS-managed. General Settings can reopen the seven-step setup guide. Skip to Privacy skips teaching steps, not diagnostic acknowledgment. Closing setup does not silently acknowledge the disclosure.

## Limits and feedback

Wireless selections remain capped at 128 files. A tested planner exists for future batches, but queue execution is disabled pending receiver/session/access-lifetime verification. No byte-level resumption is promised.

Report issues with version, macOS, broad hardware type, method and a redacted diagnostic category. Settings lets you preview and save a local diagnostic report. Review it before sharing. Never post private files, clipboard contents, credentials or pairing keys.

## Automatic diagnostics in build 23

The current candidate automatically sends diagnostics after its setup disclosure and has no reporting switches. Settings describes the policy and retains local diagnostic report preview/export. Operational reports include job/attempt outcomes, retries, USB operations, coarse stage timings, error categories, app/macOS versions and queue depth. Schema 2 adds no names, paths, file/clipboard contents or hardware identifiers. Legacy reports still include the advertised device names and Mac model described in the privacy policy. Reports retain for 90 days; pending reports retain for seven days, capped at 200.

The owner dashboard is https://nearbydrop.runs-at.dev/operations.php. Old public clients continue their existing behavior and cannot retroactively supply attempted-transfer or failure details.
