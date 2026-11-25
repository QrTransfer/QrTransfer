import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRRenderer {
    private static let context = CIContext()

    /// Renders a QR code (error correction L) at `scale` pixels per module.
    public static func image(for text: String, scale: CGFloat = 4) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
