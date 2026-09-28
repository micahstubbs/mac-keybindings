// End-to-end test against the already-running, authorized MacBindings app.
// Opens a temporary, unsaved native window. Does not test F9 or touch documents.
import AppKit
import ApplicationServices

final class LiveCheck: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var priorApp: NSRunningApplication?
    var originalCursor = CGEvent(source: nil)!.location
    var index = 0
    let cases: [(CGEventFlags, Int64, Int)] = [(.maskControl, 3, 0), (.maskCommand, 3, 1),
                                               (.maskCommand, 4, 2), ([.maskCommand, .maskShift], 3, 0)]
    var down: Int64 = 3
    var up: Int64 = 4
    let identifier = ProcessInfo.processInfo.environment["MACBINDINGS_BUNDLE_ID"] ?? defaultBundleIdentifier
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CGPreflightPostEventAccess() else {
            fputs("Live harness cannot post input; grant the launching terminal Accessibility access.\n", stderr)
            exit(2)
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else {
            fputs("Start the installed MacBindings app first.\n", stderr); exit(2)
        }
        let settings = UserDefaults(suiteName: identifier)!
        guard !settings.bool(forKey: "paused"), settings.string(forKey: "mouseMode") != "scroll" else {
            fputs("Live test requires active thumb-button mode.\n", stderr); exit(2)
        }
        if let value = settings.object(forKey: "downButton") as? Int { down = Int64(value) }
        if let value = settings.object(forKey: "upButton") as? Int { up = Int64(value) }
        priorApp = NSWorkspace.shared.frontmostApplication
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 700, height: 500),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MacBindings window movement test — closes automatically"
        window.minSize = NSSize(width: 100, height: 100)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.next() }
    }
    func finish(_ success: Bool) {
        CGWarpMouseCursorPosition(originalCursor)
        window.orderOut(nil)
        priorApp?.activate(options: [])
        fflush(stdout)
        exit(success ? 0 : 1)
    }
    func next() {
        guard index < cases.count else { print("4 live window checks passed"); finish(true); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            print("FAIL: test window lost focus to \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"); stopped without sending more input."); finish(false); return
        }
        let (flags, configuredButton, column) = cases[index]
        let button = configuredButton == 3 ? down : up
        let screens = NSScreen.screens
        let primaryTop = screens[0].frame.maxY
        let areas = screens.map { DisplayArea(frame: accessibilityRect($0.frame, primaryTop: primaryTop),
                                              visible: accessibilityRect($0.visibleFrame, primaryTop: primaryTop)) }
        let target = targetThird(window: accessibilityRect(window.frame, primaryTop: primaryTop), displays: areas, column: column)!
        let source = CGEventSource(stateID: .privateState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: CGPoint(x: window.frame.midX, y: primaryTop - window.frame.midY), mouseButton: .center)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let actual = accessibilityRect(self.window.frame, primaryTop: primaryTop)
            let okay = abs(actual.minX - target.minX) < 3 && abs(actual.minY - target.minY) < 3 &&
                       abs(actual.width - target.width) < 3 && abs(actual.height - target.height) < 3
            print("\(okay ? "PASS" : "FAIL"): live binding \(self.index + 1), actual=\(actual), expected=\(target)")
            guard okay else { self.finish(false); return }
            self.index += 1
            self.next()
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = LiveCheck()
app.delegate = delegate
app.run()
