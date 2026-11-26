# QrSender for Windows

[简体中文使用说明](../README.zh-CN.md) · [QRT2 protocol](../QrSender/README.md#protocol-v2-lt-fountain-code)

Open a file or drop it onto the window, then click **Play** or press **Space**. Scan the window with QrReceiver on your iPhone. **Color ×3** overlays three QR codes in the red, green, and blue channels. If scanning stalls, switch to **Mono**, lower **FPS**, or reduce **Block**.

## Run from source

Install the .NET 10 SDK on Windows and run this command from the repository root.

```powershell
dotnet run --project QrSender.Windows
```

## Publish a standalone executable

Run this command on Windows from the repository root. Use `win-arm64` in place of `win-x64` for Windows on Arm.

```powershell
dotnet publish QrSender.Windows -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
```

The executable is at `QrSender.Windows/bin/Release/net10.0-windows/win-x64/publish/QrSender.exe`. The published app includes the .NET runtime.
