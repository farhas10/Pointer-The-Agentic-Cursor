import XCTest
@testable import Pointer

@MainActor
final class AmbientBufferTests: XCTestCase {
    func testSummarizeNilWithInsufficientSamples() {
        let buffer = AmbientBuffer.shared
        buffer.stop()
        buffer.replaceSamplesForTesting([])
        XCTAssertNil(buffer.summarize())
    }

    func testSummarizeDedupesAndFormatsTimeline() {
        let buffer = AmbientBuffer.shared
        let now = Date.now
        buffer.replaceSamplesForTesting([
            AmbientBuffer.Sample(
                timestamp: now.addingTimeInterval(-4),
                appName: "Safari",
                bundleId: "com.apple.Safari",
                windowTitle: "GitHub",
                elementRole: "AXLink",
                elementTitle: "Pull requests"
            ),
            AmbientBuffer.Sample(
                timestamp: now.addingTimeInterval(-3),
                appName: "Safari",
                bundleId: "com.apple.Safari",
                windowTitle: "GitHub",
                elementRole: "AXLink",
                elementTitle: "Pull requests"
            ),
            AmbientBuffer.Sample(
                timestamp: now.addingTimeInterval(-1),
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "PanelViewModel.swift",
                elementRole: "AXTextArea",
                elementTitle: nil
            ),
        ])

        let summary = buffer.summarize()
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("Safari") == true)
        XCTAssertTrue(summary?.contains("Xcode") == true)
        XCTAssertEqual(summary?.filter { $0 == ";" }.count, 1)
    }
}
