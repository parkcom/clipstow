import AppKit
import SwiftUI

enum PopoverLayout {
    static let defaultSize = NSSize(width: 920, height: 600)
    static let minimumSize = NSSize(width: 820, height: 480)
    static let maximumSize = NSSize(width: 1_400, height: 1_000)
    static let widthDefaultsKey = "popoverWidth"
    static let heightDefaultsKey = "popoverHeight"

    static func clamped(_ size: NSSize) -> NSSize {
        NSSize(
            width: min(max(size.width, minimumSize.width), maximumSize.width),
            height: min(max(size.height, minimumSize.height), maximumSize.height)
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: AppStore!
    private var captureService: PasteboardCaptureService!
    private var captureTimer: Timer?
    private let shortcutMonitor: GlobalShortcutHandling = GlobalShortcutMonitor()
    private var popoverResizeObserver: NSObjectProtocol?
    private weak var observedPopoverWindow: NSWindow?
    private var isQuitRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let repository = try JSONNoteRepository()
            store = AppStore(repository: repository)
        } catch {
            let repository = UnavailableNoteRepository(underlyingError: error)
            store = AppStore(repository: repository)
        }

        configureStatusItem()
        configurePopover()
        configureCapture()
        configureShortcut()

        if ProcessInfo.processInfo.environment["CLIPSTOW_OPEN_ON_LAUNCH"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTimer?.invalidate()
        shortcutMonitor.stop()
        if let popoverResizeObserver {
            NotificationCenter.default.removeObserver(popoverResizeObserver)
        }
        _ = store.flushNow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showPopover()
        return false
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    @objc private func applicationDidResignActive() {
        captureService.syncBaseline()
    }

    func popoverDidClose(_ notification: Notification) {
        _ = store.flushNow()
        captureService.syncBaseline()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "ClipStow")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = "ClipStow — ⌥ Space"
    }

    private func configurePopover() {
        popover.contentSize = restoredPopoverSize()
        popover.behavior = store.keepsPopoverOpen ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: RootView(
                store: store,
                quitAction: { [weak self] in
                    self?.quitApplication()
                },
                resizeAction: { [weak self] size in
                    self?.resizePopover(to: size)
                }
            )
        )

        store.onKeepPopoverOpenChanged = { [weak self] keepsOpen in
            self?.popover.behavior = keepsOpen ? .applicationDefined : .transient
        }
        store.onLanguageChanged = { [weak self] in
            guard let self else { return }
            self.refreshShortcutRegistration()
            self.updateStatusIcon(captureEnabled: self.store.isCaptureEnabled)
        }
    }

    private func configureCapture() {
        captureService = PasteboardCaptureService(
            pasteboard: SystemPasteboardReader(),
            shouldIgnoreChanges: { NSApp.isActive },
            onCapture: { [weak store] text, date in
                store?.appendScratchItem(text: text, capturedAt: date)
            },
            onAccessStateChange: { [weak store] state in
                store?.updatePasteboardAccessState(state)
            }
        )

        store.onCaptureSettingChanged = { [weak self] enabled in
            self?.captureService.setEnabled(enabled)
            self?.updateStatusIcon(captureEnabled: enabled)
            self?.updateCaptureTimer(enabled: enabled)
        }
        captureService.setEnabled(store.isCaptureEnabled)
        updateStatusIcon(captureEnabled: store.isCaptureEnabled)
        updateCaptureTimer(enabled: store.isCaptureEnabled)
    }

    private func updateCaptureTimer(enabled: Bool) {
        captureTimer?.invalidate()
        captureTimer = nil
        guard enabled else { return }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureService.poll()
            }
        }
        timer.tolerance = 0.05
        captureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func configureShortcut() {
        shortcutMonitor.start { [weak self] in
            self?.togglePopover()
        }

        store.onShortcutSettingChanged = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshShortcutRegistration()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.refreshShortcutRegistration()
        }
    }

    private func refreshShortcutRegistration() {
        store.updateShortcutRegistration(
            hasShortcut: shortcutMonitor.hasShortcut,
            isRegistered: shortcutMonitor.isRegistered
        )
        let shortcut = shortcutMonitor.currentShortcutDescription
            ?? L10n.string("단축키 없음")
        statusItem.button?.toolTip = L10n.format("ClipStow — %@", shortcut)
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.prepareForPresentation(focus: .body)
        NSApp.activate(ignoringOtherApps: true)

        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
        configurePopoverWindow()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.store.editorMode == .edit else { return }
            self.store.requestFocus(.body, switchesToEditMode: false)
        }
    }

    private func updateStatusIcon(captureEnabled: Bool) {
        let symbolName = captureEnabled ? "note.text.badge.plus" : "note.text"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: captureEnabled
                ? L10n.string("ClipStow, Copy Capture 켜짐")
                : "ClipStow"
        )
        statusItem.button?.image?.isTemplate = true
    }

    private func configurePopoverWindow() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.styleMask.insert(.resizable)
        window.contentMinSize = PopoverLayout.minimumSize

        guard observedPopoverWindow !== window else { return }
        if let popoverResizeObserver {
            NotificationCenter.default.removeObserver(popoverResizeObserver)
        }

        observedPopoverWindow = window
        popoverResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor [weak self, weak window] in
                guard let self, let window, self.popover.isShown else { return }
                self.savePopoverSize(window.contentView?.bounds.size ?? self.popover.contentSize)
            }
        }
    }

    private func restoredPopoverSize() -> NSSize {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.object(forKey: PopoverLayout.widthDefaultsKey) == nil
            ? PopoverLayout.defaultSize.width
            : defaults.double(forKey: PopoverLayout.widthDefaultsKey)
        let storedHeight = defaults.object(forKey: PopoverLayout.heightDefaultsKey) == nil
            ? PopoverLayout.defaultSize.height
            : defaults.double(forKey: PopoverLayout.heightDefaultsKey)

        return PopoverLayout.clamped(NSSize(width: storedWidth, height: storedHeight))
    }

    private func savePopoverSize(_ size: NSSize) {
        let size = PopoverLayout.clamped(size)
        UserDefaults.standard.set(size.width, forKey: PopoverLayout.widthDefaultsKey)
        UserDefaults.standard.set(size.height, forKey: PopoverLayout.heightDefaultsKey)
    }

    private func resizePopover(to proposedSize: CGSize) {
        let size = PopoverLayout.clamped(proposedSize)
        popover.contentSize = size
        popover.contentViewController?.view.window?.setContentSize(size)
        savePopoverSize(size)
    }

    private func quitApplication() {
        guard !isQuitRequested else { return }
        isQuitRequested = true

        _ = store.flushNow()
        popover.animates = false
        popover.close()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApplication.shared.terminate(self)
        }
    }
}
