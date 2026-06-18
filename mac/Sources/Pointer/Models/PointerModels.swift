// Plain model types shared across modules. Kept dependency-free so
// every module can import this without pulling AppKit/SwiftUI.

import Foundation

/// Identifies the chip a user invoked. Mirrors the backend's ChipIntent.
public enum ChipIntent: String, Codable, Sendable, CaseIterable {
    case explain
    case translate
    case summarize
    case compare
    case webSearch = "web_search"
    case addToDrawer = "add_to_drawer"
    case polish
    case shorten
    case makeFormal = "make_formal"
    case reply
    case describe
    case ocr
    case explainChart = "explain_chart"
    case findSimilar = "find_similar"
    case whatDoesThisDo = "what_does_this_do"
    case clickItForMe = "click_it_for_me"
    case findBug = "find_bug"
    case refactor
    case addDocs = "add_docs"
    case fixIt = "fix_it"
    case fillWithMyInfo = "fill_with_my_info"
    case explainField = "explain_field"
    case validateBeforeSubmit = "validate_before_submit"

    public var displayName: String {
        switch self {
        case .explain: return "Explain"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .compare: return "Compare"
        case .webSearch: return "Web search"
        case .addToDrawer: return "Add to drawer"
        case .polish: return "Polish"
        case .shorten: return "Shorten"
        case .makeFormal: return "Make formal"
        case .reply: return "Reply"
        case .describe: return "Describe"
        case .ocr: return "OCR"
        case .explainChart: return "Explain chart"
        case .findSimilar: return "Find similar"
        case .whatDoesThisDo: return "What does this do?"
        case .clickItForMe: return "Click it for me"
        case .findBug: return "Find bug"
        case .refactor: return "Refactor"
        case .addDocs: return "Add docs"
        case .fixIt: return "Fix it"
        case .fillWithMyInfo: return "Fill with my info"
        case .explainField: return "Explain field"
        case .validateBeforeSubmit: return "Validate"
        }
    }
}

/// Minimal context about the foreground app at trigger time.
public struct AppContext: Codable, Sendable, Equatable {
    public var bundleId: String?
    public var appName: String?
    public var windowTitle: String?
    public var url: String?

    public init(
        bundleId: String? = nil,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil
    ) {
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case bundleId = "bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case url
    }
}

/// Compact AX snapshot of the element under the cursor at trigger time.
public struct AXSnapshot: Codable, Sendable, Equatable {
    public var role: String?
    public var subrole: String?
    public var title: String?
    public var value: String?
    public var selectedText: String?
    public var parentRole: String?
    public var redacted: Bool

    public init(
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        selectedText: String? = nil,
        parentRole: String? = nil,
        redacted: Bool = false
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.value = value
        self.selectedText = selectedText
        self.parentRole = parentRole
        self.redacted = redacted
    }

    enum CodingKeys: String, CodingKey {
        case role
        case subrole
        case title
        case value
        case selectedText = "selected_text"
        case parentRole = "parent_role"
        case redacted
    }
}

/// Everything the chips engine + panel coordinator needs about a trigger.
public struct TriggerContext: Sendable, Equatable {
    public var clickPoint: CGPoint
    public var appContext: AppContext
    public var axSnapshot: AXSnapshot?
    public var imagePngBase64: String?

    public init(
        clickPoint: CGPoint,
        appContext: AppContext = AppContext(),
        axSnapshot: AXSnapshot? = nil,
        imagePngBase64: String? = nil
    ) {
        self.clickPoint = clickPoint
        self.appContext = appContext
        self.axSnapshot = axSnapshot
        self.imagePngBase64 = imagePngBase64
    }
}

/// Wire-level request for `POST /v1/agent/ask`.
public struct AskRequest: Codable, Sendable {
    public var prompt: String
    public var chipIntent: ChipIntent?
    public var axSnapshot: AXSnapshot?
    public var imageB64: String?
    public var imageMime: String?
    public var appContext: AppContext?
    public var ambientSummary: String?
    public var location: UserLocation?
    public var adapterHint: String?
    public var panelSessionId: String?
    public var refreshContext: Bool?
    public var entityContext: [EntityContextEntry]?
    /// Pixel width of `imageB64` when using Computer Use automation.
    public var screenWidth: Int?
    /// Pixel height of `imageB64` when using Computer Use automation.
    public var screenHeight: Int?

    public init(
        prompt: String,
        chipIntent: ChipIntent? = nil,
        axSnapshot: AXSnapshot? = nil,
        imageB64: String? = nil,
        imageMime: String? = nil,
        appContext: AppContext? = nil,
        ambientSummary: String? = nil,
        location: UserLocation? = nil,
        adapterHint: String? = nil,
        panelSessionId: String? = nil,
        refreshContext: Bool? = nil,
        entityContext: [EntityContextEntry]? = nil,
        screenWidth: Int? = nil,
        screenHeight: Int? = nil
    ) {
        self.prompt = prompt
        self.chipIntent = chipIntent
        self.axSnapshot = axSnapshot
        self.imageB64 = imageB64
        self.imageMime = imageMime
        self.appContext = appContext
        self.ambientSummary = ambientSummary
        self.location = location
        self.adapterHint = adapterHint
        self.panelSessionId = panelSessionId
        self.refreshContext = refreshContext
        self.entityContext = entityContext
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
    }

    enum CodingKeys: String, CodingKey {
        case prompt
        case chipIntent = "chip_intent"
        case axSnapshot = "ax_snapshot"
        case imageB64 = "image_b64"
        case imageMime = "image_mime"
        case appContext = "app_context"
        case ambientSummary = "ambient_summary"
        case location
        case adapterHint = "adapter_hint"
        case panelSessionId = "panel_session_id"
        case refreshContext = "refresh_context"
        case entityContext = "entity_context"
        case screenWidth = "screen_width"
        case screenHeight = "screen_height"
    }
}

/// Resume the Gemini agent after client-side tool execution.
public struct AgentContinueRequest: Codable, Sendable {
    public var sessionId: String
    public var toolResults: [ToolResult]

    public struct ToolResult: Codable, Sendable {
        public var id: String
        public var name: String
        public var result: ToolResultValue
        public var screenshotB64: String?
        public var screenshotMime: String?
        public var screenWidth: Int?
        public var screenHeight: Int?

        public init(
            id: String,
            name: String,
            result: ToolResultValue,
            screenshotB64: String? = nil,
            screenshotMime: String? = nil,
            screenWidth: Int? = nil,
            screenHeight: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.result = result
            self.screenshotB64 = screenshotB64
            self.screenshotMime = screenshotMime
            self.screenWidth = screenWidth
            self.screenHeight = screenHeight
        }

        enum CodingKeys: String, CodingKey {
            case id, name, result
            case screenshotB64 = "screenshot_b64"
            case screenshotMime = "screenshot_mime"
            case screenWidth = "screen_width"
            case screenHeight = "screen_height"
        }
    }

    public enum ToolResultValue: Codable, Sendable, Equatable {
        case string(String)
        case object([String: String])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .string(s)
            } else if let o = try? container.decode([String: String].self) {
                self = .object(o)
            } else {
                self = .string("ok")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .object(let o): try container.encode(o)
            }
        }
    }

    public init(sessionId: String, toolResults: [ToolResult]) {
        self.sessionId = sessionId
        self.toolResults = toolResults
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case toolResults = "tool_results"
    }
}

/// Streaming events emitted by the backend (SSE).
public enum SseEvent: Sendable, Equatable {
    case token(String)
    case toolCall(
        name: String,
        inputJson: String,
        id: String,
        sessionId: String,
        tier: String
    )
    case citation(itemId: String, chunkId: String?)
    case error(String)
    case done(finishReason: String, sessionId: String?, agentMode: String?)
}

/* -------------------------------------------------------------------- */
/*  POST /v1/drawer/query                                                */
/* -------------------------------------------------------------------- */

/// Chips shown inside the drawer window (distinct from panel chips).
public enum DrawerChipIntent: String, Codable, Sendable, CaseIterable {
    case summarize
    case compare
    case find
    case extract
    case brief

    public var displayName: String {
        switch self {
        case .summarize: return "Summarize"
        case .compare: return "Compare"
        case .find: return "Find"
        case .extract: return "Extract"
        case .brief: return "Brief"
        }
    }
}

public struct DrawerQueryChunk: Codable, Sendable, Equatable {
    public var chunkId: String
    public var text: String

    public init(chunkId: String, text: String) {
        self.chunkId = chunkId
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case text
    }
}

/// Wire-format drawer item sent to the backend.
public enum DrawerQueryItem: Codable, Sendable, Equatable {
    case text(itemId: String, label: String?, chunks: [DrawerQueryChunk])
    case image(
        itemId: String,
        label: String?,
        imageB64: String,
        imageMime: String,
        ocrText: String?
    )
    case url(
        itemId: String,
        label: String?,
        url: String,
        extractedTextChunks: [DrawerQueryChunk]?
    )

    enum CodingKeys: String, CodingKey {
        case kind, itemId = "item_id", label, chunks
        case imageB64 = "image_b64", imageMime = "image_mime", ocrText = "ocr_text"
        case url, extractedTextChunks = "extracted_text_chunks"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let itemId, let label, let chunks):
            try container.encode("text", forKey: .kind)
            try container.encode(itemId, forKey: .itemId)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encode(chunks, forKey: .chunks)
        case .image(let itemId, let label, let imageB64, let imageMime, let ocrText):
            try container.encode("image", forKey: .kind)
            try container.encode(itemId, forKey: .itemId)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encode(imageB64, forKey: .imageB64)
            try container.encode(imageMime, forKey: .imageMime)
            try container.encodeIfPresent(ocrText, forKey: .ocrText)
        case .url(let itemId, let label, let url, let extractedTextChunks):
            try container.encode("url", forKey: .kind)
            try container.encode(itemId, forKey: .itemId)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(extractedTextChunks, forKey: .extractedTextChunks)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let itemId = try container.decode(String.self, forKey: .itemId)
        let label = try container.decodeIfPresent(String.self, forKey: .label)
        switch kind {
        case "text":
            let chunks = try container.decode([DrawerQueryChunk].self, forKey: .chunks)
            self = .text(itemId: itemId, label: label, chunks: chunks)
        case "image":
            self = .image(
                itemId: itemId,
                label: label,
                imageB64: try container.decode(String.self, forKey: .imageB64),
                imageMime: try container.decode(String.self, forKey: .imageMime),
                ocrText: try container.decodeIfPresent(String.self, forKey: .ocrText)
            )
        case "url":
            self = .url(
                itemId: itemId,
                label: label,
                url: try container.decode(String.self, forKey: .url),
                extractedTextChunks: try container.decodeIfPresent(
                    [DrawerQueryChunk].self,
                    forKey: .extractedTextChunks
                )
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "unknown drawer item kind: \(kind)"
            )
        }
    }
}

/// Wire-level request for `POST /v1/drawer/query`.
public struct DrawerQueryRequest: Codable, Sendable {
    public var drawerId: String
    public var drawerName: String?
    public var prompt: String
    public var chipIntent: DrawerChipIntent?
    public var items: [DrawerQueryItem]

    public init(
        drawerId: String,
        drawerName: String? = nil,
        prompt: String,
        chipIntent: DrawerChipIntent? = nil,
        items: [DrawerQueryItem]
    ) {
        self.drawerId = drawerId
        self.drawerName = drawerName
        self.prompt = prompt
        self.chipIntent = chipIntent
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case drawerId = "drawer_id"
        case drawerName = "drawer_name"
        case prompt
        case chipIntent = "chip_intent"
        case items
    }
}
