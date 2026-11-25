import AppKit
import QrCore
import SwiftUI

@MainActor
final class SenderModel: ObservableObject {
    @Published private(set) var fileName: String?
    @Published private(set) var fileSize = 0
    @Published private(set) var encoder: FountainEncoder?
    @Published private(set) var image: NSImage?
    @Published private(set) var shownImages = 0
    @Published var errorMessage: String?
    @Published var isPlaying = false { didSet { restartTimer() } }
    @Published var fps: Double = 8 { didSet { restartTimer() } }
    @Published var blockSize: Double = 700
    @Published var colorMode = UserDefaults.standard.object(forKey: "colorMode") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(colorMode, forKey: "colorMode")
            if !isPlaying { advance() }
        }
    }

    private var data: Data?
    private var timer: Timer?

    var channels: Int { colorMode ? 3 : 1 }
    /// Ideal time to deliver k blocks with ~20% fountain + metadata overhead, ignoring camera misses.
    var estimatedSeconds: Double { Double(encoder?.meta.k ?? 0) * 1.2 / (fps * Double(channels)) }

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
        encoder = FountainEncoder(data: data, name: fileName, blockSize: Int(blockSize))
        shownImages = 0
        advance()
        restartTimer()
    }

    private func advance() {
        guard let encoder else { image = nil; return }
        image = colorMode
            ? QRRenderer.colorImage((0 ..< 3).map { _ in encoder.next() })
            : QRRenderer.image(for: encoder.next())
        shownImages += 1
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard isPlaying, encoder != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
    }
}
