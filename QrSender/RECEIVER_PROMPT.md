# iOS receiver prompt

Build a single-screen SwiftUI iOS 16+ app "QrReceive" that receives a file sent as a looping sequence of QR codes.

**Scanning:** AVCaptureSession, back camera, preset `.hd1920x1080`, continuous autofocus, AVCaptureMetadataOutput with `.qr`. Full-screen preview layer. Handle every decoded string; never stop after the first scan; skip a string identical to the previous one cheaply.

**Frame format (ASCII):** `QRT1|<sid>|<idx>|<total>|<base64>` — split on `|` with maxSplits 4 (5 parts); ignore anything not starting with `QRT1|`. If `sid` differs from the current session, reset all state.
- `idx 0` = metadata: base64 → JSON `{"name":String,"size":Int,"z":Bool,"sha256":String(lowercase hex)}`. It repeats every ~10 frames.
- `idx 1..total-1` = data chunks: base64 → Data, store in `[Int: Data]`.

**Completion:** when metadata is present and every index `1..<total` is stored: concatenate chunks in index order; if `z` is true, decompress with `(data as NSData).decompressed(using: .zlib)` (raw deflate, Apple's format); verify SHA-256 (CryptoKit) equals `sha256`. On success: stop the session, write to `FileManager.default.temporaryDirectory/name`, success haptic, and present a share sheet (UIActivityViewController) so the user can Save to Files. On mismatch: show an error and reset.

**UI overlay:** file name, progress bar (received / (total-1)), received count, scan rate (frames/s), list of missing indices when fewer than 20 remain, Reset button.

Add `NSCameraUsageDescription` to Info.plist. Keep it to 2–3 Swift files, no third-party dependencies.
