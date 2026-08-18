import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleClipStow = Self(
        "toggleClipStow",
        initial: .init(.space, modifiers: [.option])
    )
}

@MainActor
protocol GlobalShortcutHandling: AnyObject {
    var currentShortcutDescription: String? { get }
    var hasShortcut: Bool { get }
    var isRegistered: Bool { get }
    func start(handler: @escaping () -> Void)
    func stop()
}

@MainActor
final class GlobalShortcutMonitor: GlobalShortcutHandling {
    private var eventTask: Task<Void, Never>?

    var currentShortcutDescription: String? {
        KeyboardShortcuts.getShortcut(for: .toggleClipStow)?.description
    }

    var hasShortcut: Bool {
        KeyboardShortcuts.getShortcut(for: .toggleClipStow) != nil
    }

    var isRegistered: Bool {
        KeyboardShortcuts.isEnabled(for: .toggleClipStow)
    }

    func start(handler: @escaping () -> Void) {
        stop()
        eventTask = Task { @MainActor in
            for await eventType in KeyboardShortcuts.events(for: .toggleClipStow)
                where eventType == .keyDown {
                handler()
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    deinit {
        eventTask?.cancel()
    }
}
