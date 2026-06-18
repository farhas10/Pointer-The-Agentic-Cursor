import AppKit
import Foundation

/// Governs tool execution by tier: safe and automation run immediately;
/// destructive waits up to 5s (Enter confirms early, Esc cancels).
@MainActor
final class ToolConfirmationCoordinator: ObservableObject {
    struct PendingTool: Identifiable, Equatable {
        let id: String
        let name: String
        let inputJson: String
        let tier: ToolTier
    }

    enum ToolTier: String, Equatable {
        case safe
        case automation
        case destructive

        init(raw: String) {
            switch raw {
            case "automation": self = .automation
            case "destructive": self = .destructive
            default: self = .safe
            }
        }

        var severity: Int {
            switch self {
            case .safe: return 0
            case .automation: return 1
            case .destructive: return 2
            }
        }
    }

    struct BannerState: Equatable {
        let tools: [PendingTool]
        let tier: ToolTier
        let countdown: Double?
        let message: String
    }

    static let confirmDelay: TimeInterval = 5

    @Published private(set) var banner: BannerState?
    @Published private(set) var isCancelled = false

    private var earlyConfirmRequested = false
    private var escapeMonitor: Any?
    private var localKeyMonitor: Any?

    func reset() {
        isCancelled = false
        earlyConfirmRequested = false
        banner = nil
        removeKeyMonitors()
    }

    func cancel() {
        isCancelled = true
        earlyConfirmRequested = false
        banner = nil
        removeKeyMonitors()
    }

    /// Skips the remaining countdown and runs the pending tools.
    func confirmEarly() {
        earlyConfirmRequested = true
    }

    /// Returns tool results after confirmation and execution, or nil if cancelled.
    func confirmAndExecute(
        tools: [PendingTool],
        executor: ActionExecutor,
        foregroundBundleId: String? = nil
    ) async -> [AgentContinueRequest.ToolResult]? {
        guard !tools.isEmpty else { return [] }
        isCancelled = false
        earlyConfirmRequested = false
        let resolved = tools.map { tool -> PendingTool in
            guard tool.name == "focus_app",
                  let target = bundleId(from: tool.inputJson) else { return tool }
            let tier = ActionSafetyChecker.elevatedTierForFocusApp(
                targetBundleId: target,
                foregroundBundleId: foregroundBundleId
            )
            return PendingTool(id: tool.id, name: tool.name, inputJson: tool.inputJson, tier: tier)
        }
        let tier = resolved.map(\.tier).max(by: { $0.severity < $1.severity }) ?? .safe

        switch tier {
        case .safe, .automation:
            banner = nil
        case .destructive:
            installKeyMonitors()
            let confirmed = await waitForCountdownConfirm(
                seconds: Self.confirmDelay,
                tools: resolved,
                tier: tier
            )
            removeKeyMonitors()
            banner = nil
            guard confirmed, !isCancelled else { return nil }
        }

        return await executeTools(resolved, executor: executor)
    }

    private func waitForCountdownConfirm(
        seconds: TimeInterval,
        tools: [PendingTool],
        tier: ToolTier
    ) async -> Bool {
        let steps = Int(seconds / 0.1)
        for step in 0..<steps {
            if isCancelled { return false }
            if earlyConfirmRequested { return true }
            let remaining = seconds - Double(step) * 0.1
            banner = BannerState(
                tools: tools,
                tier: tier,
                countdown: max(0, remaining),
                message: describeTools(tools)
            )
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !isCancelled
    }

    private func executeTools(
        _ tools: [PendingTool],
        executor: ActionExecutor
    ) async -> [AgentContinueRequest.ToolResult] {
        var results: [AgentContinueRequest.ToolResult] = []
        for tool in tools {
            if isCancelled { break }
            if tool.name == "click_at" {
                if let point = clickPoint(from: tool.inputJson, executor: executor) {
                    do {
                        try ActionSafetyChecker.validateClick(at: point)
                        await TargetOutlineWindow.show(at: point)
                    } catch {
                        results.append(.init(
                            id: tool.id,
                            name: tool.name,
                            result: .object(["error": error.localizedDescription])
                        ))
                        continue
                    }
                }
            } else if tool.tier == .destructive, tool.name == "run_applescript" {
                await TargetOutlineWindow.show(at: NSEvent.mouseLocation.flippedToCG())
            }
            do {
                let output = try await executor.execute(toolName: tool.name, inputJson: tool.inputJson)
                results.append(.init(id: tool.id, name: tool.name, result: .string(output)))
            } catch {
                results.append(.init(
                    id: tool.id,
                    name: tool.name,
                    result: .object(["error": error.localizedDescription])
                ))
            }
        }
        return results
    }

    private func describeTools(_ tools: [PendingTool]) -> String {
        tools.map { $0.name.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")
    }

    private func bundleId(from json: String) -> String? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object["bundle_id"] as? String
        else { return nil }
        return value
    }

    private func clickPoint(from json: String, executor: ActionExecutor) -> CGPoint? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if executor.computerUseMode {
            let x: Int?
            let y: Int?
            if let xi = object["x"] as? Int {
                x = xi
            } else if let xd = object["x"] as? Double {
                x = Int(xd)
            } else {
                x = nil
            }
            if let yi = object["y"] as? Int {
                y = yi
            } else if let yd = object["y"] as? Double {
                y = Int(yd)
            } else {
                y = nil
            }
            guard let x, let y else { return nil }
            return ComputerUseActions.denormalizedPoint(
                x: x,
                y: y,
                screenWidth: executor.screenSize.width,
                screenHeight: executor.screenSize.height
            )
        }
        guard
            let x = object["x"] as? Double,
            let y = object["y"] as? Double
        else { return nil }
        return CGPoint(x: x, y: y)
    }

    private func installKeyMonitors() {
        removeKeyMonitors()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.cancel() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:
                self.cancel()
                return nil
            case 36, 76:
                if self.banner != nil {
                    self.confirmEarly()
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }

    private func removeKeyMonitors() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}

private extension CGPoint {
    func flippedToCG() -> CGPoint {
        guard let screen = NSScreen.main else { return self }
        return CGPoint(x: x, y: screen.frame.height - y)
    }
}
