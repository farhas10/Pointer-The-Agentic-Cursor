import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Extracts text or image payloads from dropped files for drawer ingest.
enum DrawerTextExtractor {
    enum Extracted {
        case text(String)
        case image(mime: String, base64: String)
        case unsupported(String)
    }

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "yaml", "yml", "xml", "csv",
        "swift", "py", "js", "ts", "tsx", "jsx", "rb", "go", "rs", "java",
        "kt", "c", "cpp", "h", "hpp", "cs", "php", "sql", "sh", "zsh",
        "html", "css", "scss", "toml", "ini", "log", "env",
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static func extract(filename: String, data: Data) -> Extracted {
        let ext = (filename as NSString).pathExtension.lowercased()

        if imageExtensions.contains(ext), let mime = imageMime(for: ext) {
            return .image(mime: mime, base64: data.base64EncodedString())
        }

        if ext == "pdf" {
            if let text = extractPdf(data), !text.isEmpty {
                return .text(text)
            }
            return .unsupported("Could not extract text from PDF.")
        }

        if ext == "docx" {
            if let text = extractDocx(data), !text.isEmpty {
                return .text(text)
            }
            return .unsupported("Could not extract text from DOCX.")
        }

        if textExtensions.contains(ext) || ext.isEmpty {
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return .text(text)
            }
            if let text = String(data: data, encoding: .ascii), !text.isEmpty {
                return .text(text)
            }
        }

        return .unsupported("Unsupported file type: .\(ext)")
    }

    private static func imageMime(for ext: String) -> String? {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    private static func extractDocx(_ data: Data) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let docxURL = tempDir.appendingPathComponent(UUID().uuidString + ".docx")
        let txtURL = tempDir.appendingPathComponent(UUID().uuidString + ".txt")
        defer {
            try? FileManager.default.removeItem(at: docxURL)
            try? FileManager.default.removeItem(at: txtURL)
        }
        do {
            try data.write(to: docxURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "txt", "-output", txtURL.path, docxURL.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let text = try String(contentsOf: txtURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func extractPdf(_ data: Data) -> String? {
        guard let doc = PDFDocument(data: data) else { return nil }
        var parts: [String] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index),
                  let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { continue }
            parts.append(text)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
