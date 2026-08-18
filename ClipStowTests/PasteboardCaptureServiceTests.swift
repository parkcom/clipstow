import XCTest
@testable import ClipStow

final class PasteboardCaptureServiceTests: XCTestCase {
    func testDoesNothingWithoutAChangeOrWhileDisabled() {
        let pasteboard = FakePasteboard(changeCount: 10, text: "Initial")
        let captured = CaptureBox()
        let service = makeService(pasteboard: pasteboard, captured: captured)

        service.poll()
        pasteboard.changeCount = 11
        pasteboard.text = "Changed"
        service.poll()

        XCTAssertTrue(captured.values.isEmpty)
    }

    func testEnablingSetsBaselineAndCapturesOnlyNewNonemptyText() {
        let pasteboard = FakePasteboard(changeCount: 1, text: "Before enable")
        let captured = CaptureBox()
        let service = makeService(pasteboard: pasteboard, captured: captured)

        service.setEnabled(true)
        service.poll()
        XCTAssertTrue(captured.values.isEmpty)

        pasteboard.changeCount = 2
        pasteboard.text = "   "
        service.poll()
        XCTAssertTrue(captured.values.isEmpty)

        pasteboard.changeCount = 3
        pasteboard.text = "Copied"
        service.poll()
        XCTAssertEqual(captured.values, ["Copied"])
    }

    func testRepeatedTextWithNewChangeCountIsCapturedAgain() {
        let pasteboard = FakePasteboard(changeCount: 1, text: nil)
        let captured = CaptureBox()
        let service = makeService(pasteboard: pasteboard, captured: captured)
        service.setEnabled(true)

        pasteboard.changeCount = 2
        pasteboard.text = "Same"
        service.poll()
        pasteboard.changeCount = 3
        service.poll()

        XCTAssertEqual(captured.values, ["Same", "Same"])
    }

    func testInternalAppChangesAreIgnoredAndBecomeNewBaseline() {
        let pasteboard = FakePasteboard(changeCount: 1, text: nil)
        let captured = CaptureBox()
        var isAppActive = true
        let service = PasteboardCaptureService(
            pasteboard: pasteboard,
            shouldIgnoreChanges: { isAppActive },
            onCapture: { text, _ in captured.values.append(text) }
        )
        service.setEnabled(true)

        pasteboard.changeCount = 2
        pasteboard.text = "Internal"
        service.poll()
        isAppActive = false
        service.poll()

        XCTAssertTrue(captured.values.isEmpty)
    }

    func testDeniedPasteboardDoesNotReadOrCapture() {
        let pasteboard = FakePasteboard(changeCount: 1, text: "Secret", accessState: .denied)
        let captured = CaptureBox()
        var states: [PasteboardAccessState] = []
        let service = PasteboardCaptureService(
            pasteboard: pasteboard,
            shouldIgnoreChanges: { false },
            onCapture: { text, _ in captured.values.append(text) },
            onAccessStateChange: { states.append($0) }
        )
        service.setEnabled(true)
        pasteboard.changeCount = 2
        service.poll()

        XCTAssertTrue(captured.values.isEmpty)
        XCTAssertEqual(pasteboard.readCount, 0)
        XCTAssertEqual(states.last, .denied)
    }

    private func makeService(
        pasteboard: FakePasteboard,
        captured: CaptureBox
    ) -> PasteboardCaptureService {
        PasteboardCaptureService(
            pasteboard: pasteboard,
            shouldIgnoreChanges: { false },
            onCapture: { text, _ in captured.values.append(text) }
        )
    }
}

private final class CaptureBox {
    var values: [String] = []
}

private final class FakePasteboard: PasteboardReading {
    var changeCount: Int
    var text: String?
    var accessState: PasteboardAccessState
    var readCount = 0

    init(
        changeCount: Int,
        text: String?,
        accessState: PasteboardAccessState = .unrestricted
    ) {
        self.changeCount = changeCount
        self.text = text
        self.accessState = accessState
    }

    func readString() -> String? {
        readCount += 1
        return text
    }
}
