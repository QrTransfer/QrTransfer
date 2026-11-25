import AVFoundation
import Combine
import CoreImage
import UIKit
import Vision

final class QRScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Mode: String {
        case mono = "Mono"
        case color = "Color"
    }

    struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    let session = AVCaptureSession()
    @Published private(set) var progress = Transfer().progress
    @Published private(set) var mode: Mode?
    @Published private(set) var scanRate = 0.0
    @Published private(set) var message: String?
    @Published var sharedFile: SharedFile?

    // The capture session, transfer, and rate counters are owned by this queue.
    private let queue = DispatchQueue(label: "QrReceiver.capture", qos: .userInitiated)
    private var transfer = Transfer()
    private var configured = false
    private var completed = false
    private var timer: DispatchSourceTimer?
    private var decodedCount = 0
    private var lastRateSample = DispatchTime.now()
    private var detectedMode: Mode?
    private var failedSessionID: String?
    private let channelVectors = [
        CIVector(x: 1, y: 0, z: 0, w: 0),
        CIVector(x: 0, y: 1, z: 0, w: 0),
        CIVector(x: 0, y: 0, z: 1, w: 0)
    ]
    private let barcodeRequest: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        return request
    }()

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
            self.detectedMode = nil
            self.failedSessionID = nil
            self.resetRate()
            let progress = self.transfer.progress
            DispatchQueue.main.async {
                self.progress = progress
                self.mode = nil
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
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canSetSessionPreset(.hd1920x1080),
              session.canAddInput(input) else { throw CameraFailure.unavailable }
        session.sessionPreset = .hd1920x1080
        session.addInput(input)
        do {
            guard session.canAddOutput(output) else { throw CameraFailure.unavailable }
            session.addOutput(output)
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
            output.setSampleBufferDelegate(self, queue: queue)
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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !completed, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        var strings = Set<String>()
        var payloads: [String] = []
        for channel in channelVectors {
            let grayscale = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": channel,
                "inputGVector": channel,
                "inputBVector": channel
            ])
            let handler = VNImageRequestHandler(ciImage: grayscale, options: [:])
            guard (try? handler.perform([barcodeRequest])) != nil else { continue }
            for result in barcodeRequest.results ?? [] {
                if let payload = result.payloadStringValue, strings.insert(payload).inserted {
                    payloads.append(payload)
                }
            }
        }
        guard !payloads.isEmpty else { return }

        let mode: Mode = payloads.count >= 2 ? .color : .mono
        if detectedMode != mode {
            detectedMode = mode
            DispatchQueue.main.async { self.mode = mode }
        }

        let previousSessionID = transfer.sessionID
        var changed = false
        do {
            for payload in payloads where transfer.receive(payload) {
                changed = true
                if let file = try transfer.completedFile() {
                    try finish(name: file.name, data: file.data, progress: transfer.progress)
                    return
                }
            }
        } catch {
            failedSessionID = transfer.sessionID
            transfer = Transfer()
            detectedMode = nil
            resetRate()
            let emptyProgress = transfer.progress
            let message = (error as? Transfer.Failure)?.errorDescription
                ?? "The file could not be saved. Scanning has restarted."
            DispatchQueue.main.async {
                self.progress = emptyProgress
                self.mode = nil
                self.message = message
            }
            return
        }

        let sessionChanged = previousSessionID != transfer.sessionID
        if sessionChanged { resetRate() }
        decodedCount += payloads.count
        if changed {
            let progress = transfer.progress
            let clearError = sessionChanged && transfer.sessionID != failedSessionID
            if clearError { failedSessionID = nil }
            DispatchQueue.main.async {
                self.progress = progress
                if clearError { self.message = nil }
            }
        }
    }

    private func finish(name: String, data: Data, progress: Transfer.Progress) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let url = directory.appendingPathComponent(name, isDirectory: false)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        completed = true
        queue.async { self.session.stopRunning() }
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
