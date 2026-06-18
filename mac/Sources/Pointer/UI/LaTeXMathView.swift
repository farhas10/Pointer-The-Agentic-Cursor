import SwiftMath
import SwiftUI

/// Native LaTeX renderer for assistant answers (`$…$` inline, `$$…$$` display).
struct LaTeXMathView: NSViewRepresentable {
    let latex: String
    var displayMode: Bool = false
    var fontSize: CGFloat = 15

    func makeNSView(context: Context) -> MTMathUILabel {
        let view = MTMathUILabel()
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.displayErrorInline = false
        return view
    }

    func updateNSView(_ view: MTMathUILabel, context: Context) {
        view.latex = latex
        view.fontSize = displayMode ? fontSize + 1 : fontSize
        view.textAlignment = displayMode ? .center : .left
        view.labelMode = displayMode ? .display : .text
        view.textColor = NSColor.labelColor
        view.invalidateIntrinsicContentSize()
        view.layout()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MTMathUILabel,
        context: Context
    ) -> CGSize? {
        if let width = proposal.width, width.isFinite, width > 0 {
            nsView.frame.size.width = width
        }
        nsView.layout()
        return nsView.fittingSize
    }
}
