import Foundation

/// Phase 2: named project workspace ("drawer") of mixed-media items
/// the user can query as a unit.
///
/// This file declares the public model surface; the storage layer
/// lives in `Store/`, retrieval in `RAG/`, and UI in
/// `Drawer/DrawerWindow.swift`.
public struct Drawer: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DrawerItemKind: String, Codable, Sendable {
    case file
    case image
    case text
    case url
}

public struct DrawerItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var drawerId: UUID
    public var kind: DrawerItemKind
    public var label: String
    public var blobSha256: String?
    public var sizeBytes: Int64
    public var pageCount: Int?
    public var sourceUrl: String?
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        drawerId: UUID,
        kind: DrawerItemKind,
        label: String,
        blobSha256: String? = nil,
        sizeBytes: Int64 = 0,
        pageCount: Int? = nil,
        sourceUrl: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.drawerId = drawerId
        self.kind = kind
        self.label = label
        self.blobSha256 = blobSha256
        self.sizeBytes = sizeBytes
        self.pageCount = pageCount
        self.sourceUrl = sourceUrl
        self.addedAt = addedAt
    }
}
