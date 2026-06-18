import AppKit
import Foundation

/// Fetches and extracts readable text from a URL for drawer ingest.
enum DrawerUrlFetcher {
    enum FetchError: Error, LocalizedError {
        case invalidUrl
        case emptyContent
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidUrl: return "Invalid URL."
            case .emptyContent: return "No text could be extracted from the page."
            case .httpStatus(let code): return "HTTP \(code) fetching URL."
            }
        }
    }

    static func fetchText(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw FetchError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) PointerDrawer/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw FetchError.httpStatus(http.statusCode)
        }

        let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased() ?? ""

        let text: String?
        if mime.contains("html") || url.pathExtension.lowercased().isEmpty {
            text = htmlToText(data)
        } else {
            text = String(data: data, encoding: .utf8)
        }

        let trimmed = text?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 40 else { throw FetchError.emptyContent }
        return String(trimmed.prefix(80_000))
    }

    private static func htmlToText(_ data: Data) -> String? {
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        return raw
            .replacingOccurrences(of: "(?s)<script.*?</script>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?s)<style.*?</style>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }
}
