import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureSettings {
    static let longEdge = 1024
    static let jpegQuality: CGFloat = 0.75
}

enum ScreenCaptureFormat {
    case png
    case jpeg

    var mimeType: String {
        switch self {
        case .png: return "image/png"
        case .jpeg: return "image/jpeg"
        }
    }
}

struct ScreenCaptureResult {
    let b64: String
    let width: Int
    let height: Int
    let mime: String
}

/// Captures a small region around a screen point and returns it as a
/// base64-encoded image sized so the long edge is at most `size` pixels.
///
/// `ScreenCaptureKit` is the supported API on macOS 14+; it requires
/// Screen Recording permission. On failure (no permission, off-screen
/// point, transient error) this returns `nil` and the caller proceeds
/// without an image — the panel still works on AX-only context.
struct ScreenCapturer {
    func capture(
        regionAround point: CGPoint,
        size: Int,
        format: ScreenCaptureFormat = .jpeg
    ) async -> String? {
        do {
            return try await captureInternal(point: point, size: size, format: format)
        } catch {
            return nil
        }
    }

    /// Returns true when `b64` decodes to a PNG or JPEG within Gemini-friendly limits.
    static func isValidImageBase64(_ b64: String?) -> Bool {
        guard let b64, let data = Data(base64Encoded: b64) else { return false }
        guard data.count <= 4_000_000 else { return false }
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        if data.count >= pngSignature.count,
           data.prefix(pngSignature.count).elementsEqual(pngSignature) {
            return true
        }
        if data.count >= 3,
           data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF {
            return true
        }
        return false
    }

    static func isValidPngBase64(_ b64: String?) -> Bool {
        isValidImageBase64(b64)
    }

    /// Captures the main display for Computer Use automation loops.
    func captureMainDisplay(
        longEdge: Int = ScreenCaptureSettings.longEdge,
        format: ScreenCaptureFormat = .jpeg
    ) async -> ScreenCaptureResult? {
        do {
            return try await captureDisplayInternal(longEdge: longEdge, format: format)
        } catch {
            return nil
        }
    }

    private func captureDisplayInternal(
        longEdge: Int,
        format: ScreenCaptureFormat
    ) async throws -> ScreenCaptureResult? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first else {
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let pixelScale = CGFloat(display.width) / display.frame.width
        let outW = max(1, Int((display.frame.width * pixelScale).rounded()))
        let outH = max(1, Int((display.frame.height * pixelScale).rounded()))
        config.width = outW
        config.height = outH
        config.sourceRect = CGRect(origin: .zero, size: display.frame.size)
        config.showsCursor = true
        config.captureResolution = .nominal

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        let widerSide = max(cgImage.width, cgImage.height)
        let scale: CGFloat = widerSide > longEdge
            ? CGFloat(longEdge) / CGFloat(widerSide)
            : 1
        let targetWidth = max(1, Int(CGFloat(cgImage.width) * scale))
        let targetHeight = max(1, Int(CGFloat(cgImage.height) * scale))
        guard let encoded = downsampledBase64(cgImage, longEdge: longEdge, format: format),
              Self.isValidImageBase64(encoded) else {
            return nil
        }
        return ScreenCaptureResult(
            b64: encoded,
            width: targetWidth,
            height: targetHeight,
            mime: format.mimeType
        )
    }

    private func captureInternal(
        point: CGPoint,
        size: Int,
        format: ScreenCaptureFormat
    ) async throws -> String? {
        let scPoint = Self.cocoaScreenPoint(fromAccessibilityPoint: point)

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.frame.contains(scPoint) })
            ?? content.displays.first else {
            return nil
        }

        let side = CGFloat(size)
        var cropRect = CGRect(
            x: scPoint.x - side / 2,
            y: scPoint.y - side / 2,
            width: side,
            height: side
        )
        cropRect = cropRect.intersection(display.frame)
        guard cropRect.width > 1, cropRect.height > 1 else { return nil }

        let localSource = cropRect.offsetBy(
            dx: -display.frame.minX,
            dy: -display.frame.minY
        )
        let pixelScale = CGFloat(display.width) / display.frame.width
        let outW = max(1, Int((localSource.width * pixelScale).rounded()))
        let outH = max(1, Int((localSource.height * pixelScale).rounded()))

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = outW
        config.height = outH
        config.sourceRect = localSource
        config.showsCursor = false
        config.captureResolution = .nominal

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        let encoded = downsampledBase64(cgImage, longEdge: size, format: format)
        return Self.isValidImageBase64(encoded) ? encoded : nil
    }

    private static func cocoaScreenPoint(fromAccessibilityPoint point: CGPoint) -> CGPoint {
        let maxY = NSScreen.screens.map(\.frame.maxY).max()
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CGPoint(x: point.x, y: maxY - point.y)
    }

    private func downsampledBase64(
        _ image: CGImage,
        longEdge: Int,
        format: ScreenCaptureFormat
    ) -> String? {
        let scale: CGFloat
        let widerSide = max(image.width, image.height)
        if widerSide > longEdge {
            scale = CGFloat(longEdge) / CGFloat(widerSide)
        } else {
            scale = 1
        }
        let targetWidth = max(1, Int(CGFloat(image.width) * scale))
        let targetHeight = max(1, Int(CGFloat(image.height) * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        )
        guard let out = context.makeImage() else { return nil }

        let nsImage = NSBitmapImageRep(cgImage: out)
        switch format {
        case .png:
            guard let data = nsImage.representation(using: .png, properties: [:]) else {
                return nil
            }
            return data.base64EncodedString()
        case .jpeg:
            guard let data = nsImage.representation(
                using: .jpeg,
                properties: [.compressionFactor: ScreenCaptureSettings.jpegQuality]
            ) else {
                return nil
            }
            return data.base64EncodedString()
        }
    }
}
