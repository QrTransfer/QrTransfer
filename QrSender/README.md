# QrTransfer

**QrSender** — tiny macOS app that streams a file as a looping sequence of QR codes, for an iOS camera receiver (see `RECEIVER_PROMPT.md`).

## Run
```
swift run QrSender          # dev
./build-app.sh              # produces QrSender.app
swift test
./scripts/make-icon.sh      # regenerate macOS AppIcon.icns + iOS ReceiverAppIcon-1024.png
```

Drop a file on the window (or **Open…**). Space = play/pause; ◀︎/▶︎ step when paused.
Tune **FPS** (2–20) and **Chunk** (200–1500 bytes). Bigger chunks = fewer frames but denser codes; lower if the phone struggles.

## Protocol v1
`QRT1|<sid>|<idx>|<total>|<base64>`
- idx 0: JSON `{name,size,z,sha256}` (re-sent every 10 frames)
- idx 1..total-1: file bytes in order, zlib (raw deflate via `NSData.compressed(using: .zlib)`) when `z` is true
- Receiver joins, decompresses, verifies SHA-256. Reference decoder: `FrameAssembler` in `Sources/QrCore/FrameEncoder.swift`.

Throughput ≈ chunk × fps (e.g. 700 B × 8 fps ≈ 5 KB/s) — best for files up to a few MB.
