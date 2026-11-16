# Plazma S two-phone transfer and app-install test checklist

Use two Android phones (Phone A = sender, Phone B = receiver) on the same local Wi-Fi network. Install the same candidate Plazma S build on both phones. Record each phone model, Android version, app version, and Wi-Fi type. Use a fresh room for each test.

## 1. Connect and verify the room

- On Phone A, open Transfer and create a room.
- On Phone B, scan the room QR code and join.
- Confirm both phones show the correct peer/device name and the connected-device count.
- Confirm joining starts receiving automatically; no second receive confirmation should be required.

## 2. Single-file media and documents

- Send one JPG/PNG, one MP4, one MP3/M4A, and one document.
- Confirm Phone A shows **sending** and Phone B shows **receiving**, followed by **sent** and **saved**.
- Confirm files land in the matching default folders: Pictures/Plazma S, Movies/Plazma S, Music/Plazma S, and Documents/Plazma S.
- Open each received file from its saved notification or history entry.

## 3. Android app discovery and export

- On Phone A, open Apps. Confirm installed user apps show icon, app name, and APK size.
- Confirm the list is populated on Android 11+ and does not show WebAPK shortcuts as installable apps.
- Choose one app that has only a base APK and one app that has multiple split APKs (for example, language or ABI splits).
- Select the split app and send it.
- In the sender queue, confirm the app appears as **one item** named with the app name and version, with **one progress bar**. There must not be separate queue rows/progress bars for base.apk and each split.
- Confirm the room manifest contains one .plazmaapp transfer item for that app, not individual APK items.
- While the room is active, add an image or document from another tab. Confirm it joins the same room without changing the QR code and has its own queue row.

## 4. Receive, verify, and install the split app

- On Phone B, join the room. Confirm the app appears as one received app, not as multiple APK items.
- Wait for the bundle download to finish. Confirm the app is extracted into Download/Plazma S/<package-name>/ with base.apk and every split APK.
- Confirm the received app card shows the actual app icon, app name, package name, and version.
- Tap **Install**. If Plazma S is not allowed to install unknown apps, confirm Android opens Plazma S's “Allow from this source” setting. Enable it, return to Plazma S, and tap **Install** again.
- Confirm Android's package installer opens and presents the app. Approve installation and confirm Plazma S reports the final installation result.
- If the same app is already installed with a matching signature, confirm Android updates it without removing its app data.
- Do not uninstall an existing app just to test a signature conflict; that can erase its data.

## 5. Installer failure handling (use safe test APKs)

- Try a deliberately corrupted test bundle. It must fail checksum/format validation before Android's installer is opened.
- If available, test an older version over a newer installed version. Confirm the downgrade is reported clearly.
- If available, test a test APK signed with a different key for the same package. Confirm Android's signature conflict is reported clearly; do not uninstall the installed app.
- If available, test an APK built for an incompatible ABI and confirm the incompatibility is reported.
- If safe to do so, test low-storage behavior using a device with adequate data backups. Confirm Android's storage failure is shown without marking the app as installed.
- Confirm cancellation in Android's installer is reported as cancelled, not as successful.

## 6. Integrity, resume, and mixed queue

- Send a split app large enough to observe progress. Confirm the sender's single bundle item advances from 0 to 100%.
- Interrupt Phone B's Wi-Fi during the bundle transfer. Confirm the item becomes retryable and the partial bundle is retained.
- Reconnect and tap **Retry failed**. Confirm the bundle resumes, its outer SHA-256 is verified, and each extracted APK's SHA-256 is verified before install.
- Confirm already completed media/document items are not downloaded again.
- Confirm app transfer history contains one entry per app, with the package-specific install folder available.
- Confirm the app bundle is not treated as private app-data backup: only APK package files are transferred. Play Store licensing, account data, and app-private data are not included.

## 7. Save locations and room stability

- On Phone B, open Me → Settings → Save locations. Choose separate folders for Images, Videos, Music, Files, and Apps.
- Transfer one item of each type and confirm each is saved to its selected folder. Close/reopen Plazma S and verify the folder choices persist.
- Reset one type to its default and confirm only that type changes.
- Keep the room open for at least one minute. Confirm a missed manifest poll does not flicker to Disconnected or drop the connected-device count.
- Confirm both phones reach their terminal statuses and sent/received history counts match.

Record any failure message and the relevant Plazma S logs. CI verifies code, tests, and builds; only this physical two-phone run verifies real Wi-Fi, Android storage-provider, and PackageInstaller behavior.
