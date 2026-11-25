import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRRenderer {
    private static let context = CIContext()

    private static func qr(_ text: String) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        return filter.outputImage
    }

    private static func nsImage(_ image: CIImage, _ rect: CGRect) -> NSImage? {
        guard let cg = context.createCGImage(image, from: rect) else { return nil }
        return NSImage(cgImage: cg, size: rect.size)
    }

    /// Renders a QR code (error correction L) at `scale` pixels per module.
    public static func image(for text: String, scale: CGFloat = 4) -> NSImage? {
        guard let output = qr(text)?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return nsImage(output, output.extent)
    }

    /// Overlays three independent QR codes in the R, G and B channels (dark module = 0 in that channel).
    public static func colorImage(_ texts: [String], side: CGFloat = 1200) -> NSImage? {
        precondition(texts.count == 3)
        let one = CIVector(x: 1, y: 0, z: 0, w: 0), zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        var combined: CIImage?
        for (channel, text) in texts.enumerated() {
            guard let code = qr(text) else { return nil }
            let s = side / code.extent.width
            let layer = code.samplingNearest()
                .transformed(by: CGAffineTransform(scaleX: s, y: s))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": channel == 0 ? one : zero,
                    "inputGVector": channel == 1 ? one : zero,
                    "inputBVector": channel == 2 ? one : zero,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": zero,
                ])
            combined = combined.map {
                layer.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: $0])
            } ?? layer
        }
        return combined.flatMap { nsImage($0, CGRect(x: 0, y: 0, width: side, height: side)) }
    }
}
