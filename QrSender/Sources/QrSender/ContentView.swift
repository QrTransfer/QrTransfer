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
                    .disabled(model.encoded == nil)
                Button("◀︎") { model.step(-1) }.disabled(model.isPlaying || model.encoded == nil)
                Button("▶︎") { model.step(1) }.disabled(model.isPlaying || model.encoded == nil)
            }

            HStack {
                Text("FPS \(Int(model.fps))").frame(width: 70, alignment: .leading)
                Slider(value: $model.fps, in: 2 ... 20, step: 1)
            }
            HStack {
                Text("Chunk \(Int(model.chunkSize))B").frame(width: 100, alignment: .leading)
                Slider(value: $model.chunkSize, in: 200 ... 1500, step: 50) { editing in
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
        guard let encoded = model.encoded, let name = model.fileName else { return "No file" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(model.fileSize), countStyle: .file)
        return String(format: "frame %d/%d · %@ · %@%@ · loop %.0fs",
                      model.currentFrameIndex, encoded.total - 1, name, size,
                      encoded.meta.z ? " (zlib)" : "", model.loopSeconds)
    }
}
