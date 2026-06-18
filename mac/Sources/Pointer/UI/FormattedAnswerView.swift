import SwiftUI

/// Renders assistant markdown with headers, section labels, and citation chips.
struct FormattedAnswerView: View {
    let text: String
    var citationLabels: [String: String] = [:]
    var onCitationTap: ((String, String?) -> Void)?

    private var blocks: [AnswerMarkdownParser.Block] {
        text.isEmpty ? [] : AnswerMarkdownParser.parse(text)
    }

    private var allCitations: [AnswerMarkdownParser.CitationRef] {
        AnswerMarkdownParser.allCitations(in: blocks)
    }

    var body: some View {
        Group {
            if text.isEmpty {
                Text("…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else if blocks.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                    if !allCitations.isEmpty {
                        sourcesFooter
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: AnswerMarkdownParser.Block) -> some View {
        switch block {
        case .heading(let level, let title):
            headingView(level: level, title: title)
        case .paragraph(let body, _):
            contentBlock(body: body, indent: 0)
        case .bulletList(let items):
            bulletListView(items)
        case .codeBlock(let code):
            codeBlockView(code)
        case .mathBlock(let latex):
            LaTeXMathView(latex: latex, displayMode: true, fontSize: 16)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        }
    }

    private func headingView(level: Int, title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: headingIcon(level: level, title: title))
                .font(.system(size: level <= 2 ? 12 : 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(stripInlineMarkdown(title))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, level == 1 ? 2 : 0)
    }

    private func bulletListView(_ items: [AnswerMarkdownParser.BulletItem]) -> some View {
        let isNumbered = items.contains { $0.number != nil }
        return VStack(alignment: .leading, spacing: isNumbered ? 8 : 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                bulletItemView(item, numberedList: isNumbered)
            }
        }
    }

    private func bulletItemView(
        _ item: AnswerMarkdownParser.BulletItem,
        numberedList: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = item.title {
                sectionLabel(title, level: item.level)
            }

            HStack(alignment: .top, spacing: 8) {
                listMarker(for: item)

                contentBlock(
                    body: item.body,
                    indent: CGFloat(item.level) * 12 + (item.title == nil ? 0 : 4)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, item.title == nil ? CGFloat(item.level) * 12 : 0)
        }
        .padding(.vertical, numberedList ? 8 : 0)
        .padding(.horizontal, numberedList ? 10 : 0)
        .background {
            if numberedList {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }

    @ViewBuilder
    private func listMarker(for item: AnswerMarkdownParser.BulletItem) -> some View {
        if let number = item.number {
            Text("\(number).")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, alignment: .trailing)
                .padding(.top, 1)
        } else if item.title == nil {
            Image(systemName: item.level == 0 ? "circle.fill" : "circle")
                .font(.system(size: item.level == 0 ? 5 : 4))
                .foregroundStyle(item.level == 0 ? Color.accentColor : .secondary)
                .padding(.top, 6)
        }
    }

    private func sectionLabel(_ title: String, level: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: sectionIcon(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.9))
                .frame(width: 14)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, CGFloat(level) * 12)
    }

    private func contentBlock(
        body: [AnswerMarkdownParser.Inline],
        indent: CGFloat
    ) -> some View {
        inlineContentView(body)
            .padding(.leading, indent)
    }

    private enum InlineSegment: Equatable {
        case textRun([AnswerMarkdownParser.Inline])
        case latexInline(String)
        case latexDisplay(String)
    }

    private func inlineSegments(from inlines: [AnswerMarkdownParser.Inline]) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var buffer: [AnswerMarkdownParser.Inline] = []

        func flushText() {
            guard !buffer.isEmpty else { return }
            segments.append(.textRun(buffer))
            buffer = []
        }

        for inline in inlines {
            switch inline {
            case .latexInline(let latex):
                flushText()
                segments.append(.latexInline(latex))
            case .latexDisplay(let latex):
                flushText()
                segments.append(.latexDisplay(latex))
            default:
                buffer.append(inline)
            }
        }
        flushText()
        return segments
    }

    @ViewBuilder
    private func inlineContentView(_ inlines: [AnswerMarkdownParser.Inline]) -> some View {
        let segments = inlineSegments(from: inlines)
        if segments.count == 1, case .textRun(let run) = segments[0] {
            bodyText(run)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .textRun(let run):
                        bodyText(run)
                    case .latexInline(let latex):
                        LaTeXMathView(latex: latex, displayMode: false, fontSize: 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .latexDisplay(let latex):
                        LaTeXMathView(latex: latex, displayMode: true, fontSize: 16)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private var sourcesFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().opacity(0.35)
            Text("Sources")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            citationRow(allCitations)
        }
        .padding(.top, 2)
    }

    private func bodyText(_ inlines: [AnswerMarkdownParser.Inline]) -> some View {
        inlines.reduce(Text("")) { partial, inline in
            partial + inlineText(inline)
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inlineText(_ inline: AnswerMarkdownParser.Inline) -> Text {
        switch inline {
        case .text(let string):
            return Text(string)
        case .bold(let string):
            return Text(string).fontWeight(.semibold)
        case .italic(let string):
            return Text(string).italic()
        case .code(let string):
            return Text(string).font(.system(size: 12, design: .monospaced))
        case .citation:
            return Text("")
        case .latexInline, .latexDisplay:
            return Text("")
        }
    }

    private func citationRow(_ citations: [AnswerMarkdownParser.CitationRef]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(citations.enumerated()), id: \.offset) { _, ref in
                citationChip(itemId: ref.itemId, chunkId: ref.chunkId)
            }
        }
    }

    private func citationChip(itemId: String, chunkId: String?) -> some View {
        Button {
            onCitationTap?(itemId, chunkId)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "doc.text.fill")
                    .imageScale(.small)
                Text(citationLabel(itemId: itemId, chunkId: chunkId))
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .help("Jump to \(citationLabels[itemId] ?? itemId)")
    }

    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func citationLabel(itemId: String, chunkId: String?) -> String {
        let raw = citationLabels[itemId] ?? String(itemId.prefix(8))
        let trimmed: String
        if raw.count > 22 {
            trimmed = String(raw.prefix(19)) + "…"
        } else {
            trimmed = raw
        }
        _ = chunkId
        return trimmed
    }

    private func sectionIcon(_ title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("location") || lower.contains("address") { return "mappin.and.ellipse" }
        if lower.contains("date") || lower.contains("time") { return "calendar" }
        if lower.contains("item") || lower.contains("purchased") || lower.contains("order") {
            return "cart"
        }
        if lower.contains("payment") || lower.contains("total") || lower.contains("tax") {
            return "creditcard"
        }
        if lower.contains("example") { return "lightbulb.fill" }
        if lower.contains("purpose") { return "scope" }
        return "text.alignleft"
    }

    private func headingIcon(level: Int, title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("example") { return "lightbulb.fill" }
        if lower.contains("purpose") || lower.contains("overview") { return "scope" }
        if lower.contains("what happened") { return "list.bullet.rectangle.fill" }
        switch level {
        case 1: return "text.book.closed.fill"
        case 2: return "list.bullet.rectangle.fill"
        default: return "info.circle.fill"
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 15
        case 2: return 14
        default: return 13
        }
    }

    private func stripInlineMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
