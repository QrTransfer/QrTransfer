import SwiftUI

struct ContentView: View {
    @StateObject private var model = SenderModel()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            qrArea
                .frame(width: 620, height: 620)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.load(url: url)
                    return true
                } isTargeted: { isTargeted = $0 }

            Text(statusText).font(.system(.body, design: .monospaced))
            if let error = model.errorMessage { Text(error).foregroundColor(.red) }

            HStack(spacing: 16) {
                Button("Open…") { model.openPanel() }
                Button(model.isPlaying ? "Pause" : "Play") { model.isPlaying.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.encoder == nil)
                Picker("Code", selection: $model.colorMode) {
                    Text("Mono").tag(false)
                    Text("Color ×3").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .help("Color overlays 3 QR codes in R/G/B (3× throughput). Use Mono if the phone decodes poorly.")
            }

            HStack {
                Text("FPS \(Int(model.fps))").frame(width: 70, alignment: .leading)
                Slider(value: $model.fps, in: 2 ... 20, step: 1)
            }
            HStack {
                Text("Block \(Int(model.blockSize))B").frame(width: 100, alignment: .leading)
                Slider(value: $model.blockSize, in: 200 ... 1500, step: 50) { editing in
                    if !editing { model.reencode() }
                }
            }
        }
        .padding(20)
        .frame(width: 660)
    }

    @ViewBuilder private var qrArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isTargeted ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isTargeted ? 4 : 1))
            if let image = model.image {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(24)
            } else {
                Text("Drop a file here or click Open…")
                    .foregroundColor(.gray)
            }
        }
    }

    private var statusText: String {
        guard let meta = model.encoder?.meta, let name = model.fileName else { return "No file" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.fileSize), countStyle: .file)
        return String(format: "%@ · shown %d · %d blocks · %@ · %@%@ · ≈%.0fs",
                      model.colorMode ? "color" : "mono", model.shownImages, meta.k, name, size,
                      meta.z ? " (zlib)" : "", model.estimatedSeconds)
    }
}
