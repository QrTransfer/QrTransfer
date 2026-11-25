# iOS receiver prompt

Build a single-screen SwiftUI iOS 16+ app "QrReceiver" that receives a file shown on a Mac as a stream of (possibly colour) QR codes. Apple frameworks only, 2–3 Swift files, add `NSCameraUsageDescription`.

**Capture:** AVCaptureSession, back camera, `.hd1920x1080`, continuous autofocus, AVCaptureVideoDataOutput (BGRA, `alwaysDiscardsLateVideoFrames`, serial background queue). The sender may show mono or colour codes; handle both automatically with one pipeline. A colour image carries 3 independent QR codes, one per channel: for each of R, G, B, use `CIColorMatrix` to copy that channel into r, g and b (grayscale), then run `VNDetectBarcodesRequest` (symbologies `[.qr]`) and collect every `payloadStringValue`. A mono QR just yields the same string 3×. Skip strings already seen (`Set` of `hashValue`). Show the detected mode: "Color" if one camera frame gives ≥2 distinct strings, otherwise "Mono".

**Frames** — split on `|`, ignore unless field 0 is `QRT2`; if `sid` changes, reset everything:
- `QRT2|<sid>|M|<base64 JSON>` metadata `{"name":String,"size":Int,"z":Bool,"sha256":hex,"k":Int,"b":Int,"len":Int}` (k source blocks of b bytes).
- `QRT2|<sid>|D|<i1,i2,…>|<base64>` fountain symbol = XOR of source blocks i1, i2, … (0-based).

**Decode (LT peeling):** keep `known:[Int:Data]` and `pending:[(Set<Int>,Data)]`. For each symbol, XOR out every index already known; 0 left → drop; >1 left → append to pending; exactly 1 → store it in known, then re-process every pending entry containing that index (cascade). Done when metadata is present and all 0..<k are known: concatenate blocks in order, keep the first `len` bytes, if `z` then `(data as NSData).decompressed(using: .zlib)`, check SHA-256 (CryptoKit) equals `sha256`. On success, stop the camera, write to the temp dir as `name`, play a success haptic, and present UIActivityViewController. On mismatch, show an error and reset.

**UI overlay:** file name, detected mode, progress bar known/k, symbols received, QR decodes/s, Reset button.
