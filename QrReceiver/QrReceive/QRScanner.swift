import AVFoundation
import Combine
import UIKit

final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    let session = AVCaptureSession()
    @Published private(set) var progress = Transfer().progress
    @Published private(set) var scanRate = 0.0
    @Published private(set) var message: String?
    @Published var sharedFile: SharedFile?

    // The capture session, transfer, and rate counters are owned by this queue.
    private let queue = DispatchQueue(label: "QrReceive.capture", qos: .userInitiated)
    private var transfer = Transfer()
    private var configured = false
    private var completed = false
    private var timer: DispatchSourceTimer?
    private var decodedCount = 0
    private var lastRateSample = DispatchTime.now()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.startCapture() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.queue.async { self.startCapture() }
                } else {
                    self.showCameraPermissionMessage()
                }
            }
        default:
            showCameraPermissionMessage()
        }
    }

    func reset() {
        queue.async {
            self.transfer = Transfer()
            self.completed = false
            self.resetRate()
            let progress = self.transfer.progress
            DispatchQueue.main.async {
                self.progress = progress
                self.message = nil
                self.start()
            }
        }
    }

    private func showCameraPermissionMessage() {
        DispatchQueue.main.async {
            self.message = "Allow camera access in Settings to scan QR codes."
        }
    }

    private func startCapture() {
        guard !completed, !session.isRunning else { return }
        if !configured {
            do {
                try configureCapture()
                configured = true
            } catch {
                DispatchQueue.main.async { self.message = error.localizedDescription }
                return
            }
        }
        session.startRunning()
        resetRate()
        if timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
            timer.setEventHandler { [weak self] in self?.publishRate() }
            self.timer = timer
            timer.resume()
        }
    }

    private enum CameraFailure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "A back camera with 1080p QR scanning is unavailable."
        }
    }

    private func configureCapture() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { throw CameraFailure.unavailable }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureMetadataOutput()

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canSetSessionPreset(.hd1920x1080),
              session.canAddInput(input) else { throw CameraFailure.unavailable }
        session.sessionPreset = .hd1920x1080
        session.addInput(input)
        do {
            guard session.canAddOutput(output) else { throw CameraFailure.unavailable }
            session.addOutput(output)
            guard output.availableMetadataObjectTypes.contains(.qr) else { throw CameraFailure.unavailable }
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
            output.setMetadataObjectsDelegate(self, queue: queue)
            output.metadataObjectTypes = [.qr]
        } catch {
            if session.outputs.contains(output) { session.removeOutput(output) }
            session.removeInput(input)
            throw error
        }
    }

    private func resetRate() {
        decodedCount = 0
        lastRateSample = .now()
        DispatchQueue.main.async { self.scanRate = 0 }
    }

    private func publishRate() {
        let now = DispatchTime.now()
        let seconds = Double(now.uptimeNanoseconds - lastRateSample.uptimeNanoseconds) / 1_000_000_000
        guard seconds > 0 else { return }
        let rate = Double(decodedCount) / seconds
        decodedCount = 0
        lastRateSample = now
        DispatchQueue.main.async { self.scanRate = rate }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        for object in metadataObjects {
            guard !completed else { break }
            guard let string = (object as? AVMetadataMachineReadableCodeObject)?.stringValue else { continue }
            let previousSessionID = transfer.sessionID
            let changed = transfer.receive(string)
            if previousSessionID != transfer.sessionID { resetRate() }
            decodedCount += 1
            guard changed else { continue }

            let progress = transfer.progress
            do {
                if let file = try transfer.completedFile() {
                    try finish(name: file.name, data: file.data, progress: progress)
                } else {
                    DispatchQueue.main.async { self.progress = progress }
                }
            } catch {
                transfer = Transfer()
                resetRate()
                let emptyProgress = transfer.progress
                let message = (error as? Transfer.Failure)?.errorDescription
                    ?? "The file could not be saved. Scanning has restarted."
                DispatchQueue.main.async {
                    self.progress = emptyProgress
                    self.message = message
                }
                startCapture()
            }
        }
    }

    private func finish(name: String, data: Data, progress: Transfer.Progress) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: false)
        session.stopRunning()
        try data.write(to: url, options: .atomic)
        completed = true
        transfer = Transfer()
        timer?.cancel()
        timer = nil
        DispatchQueue.main.async {
            self.scanRate = 0
            self.progress = progress
            self.message = "File verified and ready to share."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.sharedFile = SharedFile(url: url)
        }
    }
}
