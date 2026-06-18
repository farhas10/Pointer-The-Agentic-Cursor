import XCTest
@testable import Pointer

final class ChipsEngineTests: XCTestCase {
    func testCodeEditorBundleIdGetsCodeChips() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.microsoft.VSCode", appName: "Visual Studio Code"),
            axSnapshot: AXSnapshot(role: "AXTextArea", value: "func foo() {}")
        )
        let chips = ChipsEngine().chipSet(for: context)
        XCTAssertEqual(chips.first, .explain)
        XCTAssertTrue(chips.contains(.findBug))
        XCTAssertTrue(chips.contains(.refactor))
        XCTAssertTrue(chips.contains(.addToDrawer))
    }

    func testMailComposeFieldGetsComposeChips() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.apple.mail", appName: "Mail"),
            axSnapshot: AXSnapshot(role: "AXTextArea", title: "Message", value: "Hi there,")
        )
        let engine = ChipsEngine()
        XCTAssertEqual(engine.classify(context), .composeField)
        XCTAssertEqual(engine.chipSet(for: context).first, .polish)
    }

    func testBrowserParentRoleClassifiesAsBrowserText() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.apple.Safari", appName: "Safari"),
            axSnapshot: AXSnapshot(
                role: "AXStaticText",
                value: "Hello world",
                parentRole: "AXWebArea"
            )
        )
        let chips = ChipsEngine().chipSet(for: context)
        XCTAssertTrue(chips.contains(.translate))
        XCTAssertTrue(chips.contains(.summarize))
        XCTAssertTrue(chips.contains(.webSearch))
    }

    func testButtonElementGetsActionChips() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.apple.Safari"),
            axSnapshot: AXSnapshot(role: "AXButton", title: "Subscribe")
        )
        XCTAssertEqual(ChipsEngine().classify(context), .button)
    }

    func testImageOnlyContextClassifies() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.figma.Desktop"),
            axSnapshot: AXSnapshot(role: "AXImage"),
            imagePngBase64: "AAAA"
        )
        XCTAssertEqual(ChipsEngine().classify(context), .imageOnly)
    }

    func testGeneralFallback() {
        let context = TriggerContext(
            clickPoint: .zero,
            appContext: AppContext(bundleId: "com.unknown.App"),
            axSnapshot: nil
        )
        XCTAssertEqual(ChipsEngine().classify(context), .general)
        XCTAssertEqual(ChipsEngine().chipSet(for: context).first, .explain)
    }

    func testAddToDrawerIsAlwaysPresent() {
        for heuristicSeed in 0..<5 {
            let role: String
            switch heuristicSeed {
            case 0: role = "AXTextArea"
            case 1: role = "AXButton"
            case 2: role = "AXStaticText"
            case 3: role = "AXImage"
            default: role = "AXUnknown"
            }
            let context = TriggerContext(
                clickPoint: .zero,
                appContext: AppContext(bundleId: "com.unknown.App"),
                axSnapshot: AXSnapshot(role: role)
            )
            let chips = ChipsEngine().chipSet(for: context)
            XCTAssertTrue(
                chips.contains(.addToDrawer),
                "Add to drawer should always be available; got \(chips) for role \(role)"
            )
        }
    }
}
