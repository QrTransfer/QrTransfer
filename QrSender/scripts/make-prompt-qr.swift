// Encodes a text file into one QR PNG (level M, falls back to L). Usage: swift scripts/make-prompt-qr.swift <in.md> <out.png>
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let args = CommandLine.arguments
let text = try! String(contentsOfFile: args[1], encoding: .utf8)
var level = "M"
var code: CIImage?
for l in ["M", "L"] {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = l
    if let out = filter.outputImage { code = out; level = l; break }
}
guard let code else { fatalError("text too long for a single QR code (\(text.utf8.count) bytes)") }

let qr = code.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
let bg = CIImage(color: .white).cropped(to: qr.extent.insetBy(dx: -40, dy: -40))
let out = qr.composited(over: bg)
let cg = CIContext().createCGImage(out, from: out.extent)!
try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))

let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
let decoded = (detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString
print("\(text.utf8.count) bytes, level \(level), \(cg.width)px, round-trip \(decoded == text ? "OK" : "FAILED")")
