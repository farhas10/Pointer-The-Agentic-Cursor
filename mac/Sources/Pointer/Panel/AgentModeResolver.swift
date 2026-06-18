import Foundation

/// Mirrors backend `resolveAgentMode` so the Mac client captures the right context.
enum AgentModeResolver {
    /// Computer Use + full-screen capture — action chips only.
    static func resolvesToAutomation(prompt: String, chip: ChipIntent?) -> Bool {
        _ = prompt
        guard let chip else { return false }
        switch chip {
        case .clickItForMe, .fillWithMyInfo, .validateBeforeSubmit:
            return true
        default:
            return false
        }
    }

    static func isQaFastChip(_ chip: ChipIntent?) -> Bool {
        guard let chip else { return false }
        switch chip {
        case .explain, .translate, .summarize, .compare, .polish, .shorten,
             .makeFormal, .reply, .describe, .ocr, .explainChart, .findSimilar,
             .whatDoesThisDo, .explainField, .findBug, .refactor, .addDocs, .fixIt:
            return true
        default:
            return false
        }
    }
}
