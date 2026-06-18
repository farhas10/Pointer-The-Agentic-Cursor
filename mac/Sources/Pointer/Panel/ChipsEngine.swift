import Foundation

/// Pure logic that maps a `TriggerContext` into the 4–6 chip set the
/// panel should show. Kept dependency-free so it can be unit-tested in
/// isolation; no AppKit, no SwiftUI.
///
/// Adding a new context-class is a matter of adding a new case to
/// `Heuristic` and a row in `chipSet(for:)`.
struct ChipsEngine {
    /// Returns the chips to show, in display order. The first chip is
    /// the default highlight.
    func chipSet(for context: TriggerContext) -> [ChipIntent] {
        switch classify(context) {
        case .codeEditor:
            return [.explain, .findBug, .refactor, .addDocs, .fixIt, .addToDrawer]
        case .composeField:
            return [.polish, .shorten, .makeFormal, .reply, .addToDrawer]
        case .formField:
            return [.fillWithMyInfo, .explainField, .validateBeforeSubmit, .addToDrawer]
        case .browserText:
            return [.explain, .translate, .summarize, .webSearch, .addToDrawer]
        case .imageOnly:
            return [.describe, .ocr, .explainChart, .findSimilar, .addToDrawer]
        case .button:
            return [.whatDoesThisDo, .clickItForMe, .webSearch, .addToDrawer]
        case .general:
            return [.explain, .summarize, .translate, .webSearch, .addToDrawer]
        }
    }

    /// Visible to tests so we can assert classification behavior cleanly.
    func classify(_ context: TriggerContext) -> Heuristic {
        let ax = context.axSnapshot
        let role = ax?.role ?? ""
        let bundle = context.appContext.bundleId ?? ""
        let appName = context.appContext.appName ?? ""

        if isCodeEditor(bundleId: bundle, appName: appName) {
            return .codeEditor
        }

        if role == "AXTextField" || role == "AXTextArea" {
            // Compose-y: titles like "Subject", "Message", or being inside Mail.app.
            let title = (ax?.title ?? "").lowercased()
            if bundle == "com.apple.mail"
                || bundle == "com.tinyspeck.slackmacgap"
                || bundle == "com.microsoft.Outlook"
                || ["message", "subject", "compose", "reply"].contains(where: title.contains) {
                return .composeField
            }
            // Otherwise treat plain text fields as form fields.
            return .formField
        }

        if role == "AXButton" || role == "AXMenuButton" || role == "AXPopUpButton" {
            return .button
        }

        // Browser-y heuristics: known browser bundles or AXWebArea ancestor.
        if isBrowser(bundleId: bundle) || ax?.parentRole == "AXWebArea" {
            return .browserText
        }

        // No AX text but we do have an image → vision-only flow.
        if (ax?.value ?? "").isEmpty
            && (ax?.selectedText ?? "").isEmpty
            && context.imagePngBase64 != nil
        {
            return .imageOnly
        }

        return .general
    }

    enum Heuristic: String, Equatable {
        case codeEditor
        case composeField
        case formField
        case browserText
        case imageOnly
        case button
        case general
    }

    private func isCodeEditor(bundleId: String, appName: String) -> Bool {
        let bundles: Set<String> = [
            "com.microsoft.VSCode",
            "com.apple.dt.Xcode",
            "com.jetbrains.intellij",
            "com.jetbrains.WebStorm",
            "com.jetbrains.pycharm",
            "com.todesktop.230313mzl4w4u92",  // Cursor
            "co.zeit.hyper",
            "com.sublimetext.4",
            "com.panic.Nova",
        ]
        if bundles.contains(bundleId) { return true }
        let nameNeedles = ["xcode", "vscode", "vs code", "cursor", "sublime", "intellij", "webstorm", "pycharm", "nova"]
        let lower = appName.lowercased()
        return nameNeedles.contains(where: lower.contains)
    }

    private func isBrowser(bundleId: String) -> Bool {
        let bundles: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "com.brave.Browser",
            "company.thebrowser.Browser", // Arc
        ]
        return bundles.contains(bundleId)
    }
}
