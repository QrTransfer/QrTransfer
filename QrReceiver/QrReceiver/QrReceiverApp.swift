import AVFoundation
import SwiftUI
import UIKit

@main
struct QrReceiverApp: App {
    var body: some Scene {
        WindowGroup {
            ReceiverView()
                .preferredColorScheme(.dark)
        }
    }
}

private struct ReceiverView: View {
    @StateObject private var scanner = QRScanner()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.72), location: 0),
                    .init(color: .clear, location: 0.30),
                    .init(color: .clear, location: 0.56),
                    .init(color: .black.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                header
                Spacer(minLength: 12)
                transferPanel
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear { scanner.start() }
        .sheet(item: $scanner.sharedFile) { file in
            ShareSheet(url: file.url)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Label("QrReceiver", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Reset") { scanner.reset() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
    }

    private var transferPanel: some View {
        let progress = scanner.progress
        return VStack(alignment: .leading, spacing: 12) {
            Text(progress.name ?? "Waiting for file")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            ProgressView(
                value: progress.expected == 0 && progress.name != nil ? 1 : Double(progress.known),
                total: Double(max(progress.expected, 1))
            )
                .tint(.mint)
                .accessibilityLabel("File transfer progress")
            HStack {
                Text("\(progress.known) / \(progress.expected) blocks")
                Spacer()
                Text(scanner.mode?.rawValue ?? "Waiting for QR")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            HStack {
                Text("\(progress.symbols) symbols")
                Spacer()
                Text("\(scanner.scanRate, format: .number.precision(.fractionLength(1))) QR decodes/s")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            if let message = scanner.message {
                Text(message)
                    .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.orientPreview()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            orientPreview()
        }

        func orientPreview() {
            guard let connection = previewLayer.connection else { return }
            if #available(iOS 17.0, *) {
                if connection.videoRotationAngle != 90, connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            } else if connection.videoOrientation != .portrait, connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
