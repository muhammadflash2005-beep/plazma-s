# Plazma S phone-to-phone transfer test checklist

Run on two Android phones connected to the same Wi-Fi network. Use a fresh room for each pass.

1. **Image**
   - Phone A creates a room and shares one JPG or PNG.
   - Phone B scans the QR code. Confirm the download starts without tapping "Receive all files".
   - Confirm Phone A shows **sending** and Phone B shows **receiving**, then A shows **sent** and B shows **saved**.
   - Confirm the image appears in Gallery under **Pictures/Plazma S** and the in-app saved message offers **Open**.

2. **Video and music**
   - Repeat with one MP4 and one MP3/M4A.
   - Confirm the files appear under **Movies/Plazma S** and **Music/Plazma S**.
   - Confirm each item has its own progress and completion state.

3. **App**
   - Share an Android app with a single APK, then (if available) one with split APKs.
   - Confirm the received app appears under **Download/Plazma S**, history shows one app entry (not one per split), and **Install** opens Android's installer.
   - Confirm Plazma S sends the user to Android's unknown-app install setting when permission is disabled.

4. **Multiple items**
   - Add an image, video, music file, document, and app to one room.
   - Add another item while the first batch is transferring.
   - Confirm the receiver picks up the live manifest update without rejoining and saves each type to its matching folder.

5. **Wi-Fi interruption and retry**
   - Start a multi-file transfer, then turn Wi-Fi off on Phone B mid-transfer.
   - Confirm completed items remain saved, unfinished items become retryable, and the UI does not stay stuck at 100%.
   - Turn Wi-Fi back on and tap **Retry failed**.
   - Confirm only failed items resume, already-saved items are not downloaded again, and both phones reach their terminal states.

6. **History and room stability**
   - Check Sent and Received counts for Files, Apps, Images, Videos, and Music; names and timestamps should match the completed items.
   - Leave the room open for at least one minute. Confirm a missed poll does not briefly show Disconnected or drop the connected-device count.
   - Confirm the receiver is shown by its actual Android manufacturer/model, not localhost.

Record the Android versions, phone models, file sizes, and any failure logs for each run. These are physical-device checks; CI cannot substitute for them.
