import AppKit
import QrCore
import SwiftUI

@MainActor
final class SenderModel: ObservableObject {
    @Published private(set) var fileName: String?
    @Published private(set) var fileSize = 0
    @Published private(set) var encoded: EncodedFile?
    @Published private(set) var position = 0
    @Published private(set) var image: NSImage?
    @Published var errorMessage: String?
    @Published var isPlaying = false { didSet { restartTimer() } }
    @Published var fps: Double = 8 { didSet { restartTimer() } }
    @Published var chunkSize: Double = 700

    private var data: Data?
    private var timer: Timer?

    var currentFrameIndex: Int { encoded.map { $0.playlist[position] } ?? 0 }
    var loopSeconds: Double { Double(encoded?.playlist.count ?? 0) / fps }

    func load(url: URL) {
        do {
            let d = try Data(contentsOf: url)
            data = d
            fileName = url.lastPathComponent
            fileSize = d.count
            errorMessage = nil
            isPlaying = false
            reencode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    func reencode() {
        guard let data, let fileName else { return }
        encoded = FrameEncoder.encode(data: data, name: fileName, chunkSize: Int(chunkSize))
        position = 0
        render()
        restartTimer()
    }

    func step(_ delta: Int) {
        guard let count = encoded?.playlist.count, count > 0 else { return }
        position = (position + delta + count) % count
        render()
    }

    private func render() {
        guard let encoded else { image = nil; return }
        image = QRRenderer.image(for: encoded.frames[encoded.playlist[position]])
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard isPlaying, encoded != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step(1) }
        }
    }
}
