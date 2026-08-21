import AppKit
import Foundation

enum PasteboardAccessState: Equatable {
    case unrestricted
    case asksPermission
    case denied
}

protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var accessState: PasteboardAccessState { get }
    func readString() -> String?
}

final class SystemPasteboardReader: PasteboardReading {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    var accessState: PasteboardAccessState {
        if #available(macOS 26.0, *) {
            switch pasteboard.accessBehavior {
            case .alwaysDeny:
                return .denied
            case .ask, .default:
                return .asksPermission
            case .alwaysAllow:
                return .unrestricted
            @unknown default:
                return .asksPermission
            }
        }
        return .unrestricted
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }
}

final class PasteboardCaptureService {
    private let pasteboard: PasteboardReading
    private let shouldIgnoreChanges: () -> Bool
    private let onCapture: (String, Date) -> Void
    private let onAccessStateChange: (PasteboardAccessState) -> Void
    private let now: () -> Date

    private(set) var isEnabled = false
    private(set) var lastChangeCount: Int

    init(
        pasteboard: PasteboardReading,
        shouldIgnoreChanges: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init,
        onCapture: @escaping (String, Date) -> Void,
        onAccessStateChange: @escaping (PasteboardAccessState) -> Void = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.shouldIgnoreChanges = shouldIgnoreChanges
        self.now = now
        self.onCapture = onCapture
        self.onAccessStateChange = onAccessStateChange
        lastChangeCount = pasteboard.changeCount
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        syncBaseline()
        onAccessStateChange(pasteboard.accessState)
    }

    func syncBaseline() {
        lastChangeCount = pasteboard.changeCount
    }

    func poll() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount
        guard isEnabled else { return }
        guard !shouldIgnoreChanges() else { return }

        let accessState = pasteboard.accessState
        onAccessStateChange(accessState)
        guard accessState != .denied else { return }
        guard let text = pasteboard.readString() else {
            onAccessStateChange(pasteboard.accessState)
            return
        }
        guard text.containsNonWhitespaceAndNewline else { return }

        onCapture(text, now())
        onAccessStateChange(pasteboard.accessState)
    }
}
