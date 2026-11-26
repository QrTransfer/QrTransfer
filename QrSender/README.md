# QrSender

[简体中文使用说明](../README.zh-CN.md) · [Windows version](../QrSender.Windows/)

QrSender streams a file as a fountain-coded sequence of QR codes. See the [project README](../README.md) for iPhone setup and the [receiver specification](RECEIVER_PROMPT.md) for decoding details.

## Run
```
swift run QrSender          # dev
./build-app.sh              # produces QrSender.app
swift test
./scripts/make-icon.sh      # regenerate macOS AppIcon.icns + iOS ReceiverAppIcon-1024.png
swift scripts/make-prompt-qr.swift RECEIVER_PROMPT.md RECEIVER_PROMPT.png
```

Drop a file on the window (or **Open…**), then **Play** (Space).
- **Color ×3** overlays three QR codes in the red, green, and blue channels. Switch to **Mono** if scanning stalls.
- **FPS** (2–20) and **Block** (200–1500 bytes). Lower either if the phone struggles.

## Protocol v2 (LT fountain code)
- `QRT2|<sid>|M|<base64 JSON>` — `{name,size,z,sha256,k,b,len}`, sent first and repeated every 10 symbols.
- `QRT2|<sid>|D|<i1,i2,…>|<base64>` — XOR of source blocks (robust soliton degrees, max 100).
- The receiver reconstructs the file once the received symbols supply enough information to solve all source blocks. The number of symbols needed varies with the file and which symbols arrive.
- Payload is zlib (raw deflate via `NSData.compressed(using: .zlib)`) when `z` is true, then split into k blocks of b bytes (zero-padded; trim to `len`).
- Reference decoder: `FountainDecoder` in `Sources/QrCore/Fountain.swift`.

The sender estimates transfer time from the block count, playback rate, and number of channels, with a 20% allowance for protocol overhead. Camera misses can make the transfer take longer.
