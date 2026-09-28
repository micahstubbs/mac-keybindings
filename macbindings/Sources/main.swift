import AppKit
import ApplicationServices

func log(_ message: String) {
    print("\(ISO8601DateFormatter().string(from: Date())) \(message)")
    fflush(stdout)
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func windowRect(_ window: AXUIElement) -> CGRect? {
    guard let p = attribute(window, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = attribute(window, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
          AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}

func moveWindow(pid: pid_t, displays: [DisplayArea], column: Int) -> String {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    guard let ref = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(ref) == AXUIElementGetTypeID() else {
        return "No focused window in the frontmost app."
    }
    let window = ref as! AXUIElement
    if attribute(window, "AXFullScreen") as? Bool == true { return "Exit full screen before moving this window." }
    guard let original = windowRect(window),
          let target = targetThird(window: original, displays: displays, column: column) else {
        return "Could not read the window or display bounds."
    }
    for name in [kAXPositionAttribute, kAXSizeAttribute] {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, name as CFString, &settable) == .success, settable.boolValue else {
            return "This window does not support moving and resizing."
        }
    }
    var point = target.origin
    var size = target.size
    let position = AXValueCreate(.cgPoint, &point)!
    let dimensions = AXValueCreate(.cgSize, &size)!
    // Resize before moving to fit the target monitor; repeat after moving for cross-display constraints.
    let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    let moveResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    let finalSize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    guard moveResult == .success, finalSize == .success else {
        return "Window change failed (position \(moveResult.rawValue), size \(sizeResult.rawValue)/\(finalSize.rawValue))."
    }
    guard let actual = windowRect(window) else { return "Moved window; could not verify its bounds." }
    let tolerance: CGFloat = 3
    if abs(actual.width - target.width) > tolerance || abs(actual.height - target.height) > tolerance ||
       abs(actual.minX - target.minX) > tolerance || abs(actual.minY - target.minY) > tolerance {
        return "App constrained the window size or position; exact thirds unavailable."
    }
    return "Moved to \(["left", "middle", "right"][column]) third."
}

final class MacBindings: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var router = BindingRouter()
    var learning: (down: Bool, deadline: Date)?
    var learnedButtons = Set<Int64>()
    var lastResult = "Ready"
    let worker = DispatchQueue(label: (Bundle.main.bundleIdentifier ?? defaultBundleIdentifier) + ".actions")
    let defaults = UserDefaults.standard
    let dryRun = CommandLine.arguments.contains("--dry-run")
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A single handler per login session, including manual launches alongside launchd.
        let identifier = Bundle.main.bundleIdentifier ?? defaultBundleIdentifier
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if peers.contains(where: { $0.processIdentifier != getpid() && $0.processIdentifier < getpid() }) {
            log("Another MacBindings instance is already running.")
            NSApp.terminate(nil)
            return
        }
        router.config.mode = MouseMode(rawValue: defaults.string(forKey: "mouseMode") ?? "buttons") ?? .buttons
        if let down = defaults.object(forKey: "downButton") as? Int { router.config.downButton = Int64(down) }
        if let up = defaults.object(forKey: "upButton") as? Int { router.config.upButton = Int64(up) }
        if router.config.downButton < 2 || router.config.upButton < 2 || router.config.downButton == router.config.upButton {
            router.config = BindingConfig()
        }
        router.paused = defaults.bool(forKey: "paused")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Ⅲ"
        statusItem.button?.toolTip = "MacBindings — window thirds and shortcuts"
        refreshMenu()
        tryStart()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let learning = self.learning, learning.deadline < Date() {
                self.learning = nil
                self.lastResult = "Button learning timed out; try again."
                self.refreshMenu()
            }
            self.tryStart()
        }
        log("MacBindings started; mouse mode=\(router.config.mode.rawValue), down=\(router.config.downButton), up=\(router.config.upButton), dryRun=\(dryRun)")
    }

    func tryStart() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            lastResult = "Grant Accessibility, then Retry permissions."
            refreshMenu()
            return
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                               eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MacBindings>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            lastResult = "Event access unavailable; grant Input Monitoring and retry."
            refreshMenu()
            return
        }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lastResult = "Shortcuts are active"
        log(lastResult)
        refreshMenu()
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Preserve paired releases across a re-enable.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("Re-enabled event tap after system interruption")
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker { return Unmanaged.passUnretained(event) }
        let code = event.getIntegerValueField(type == .keyDown || type == .keyUp ? .keyboardEventKeycode : .mouseEventButtonNumber)
        if type == .otherMouseUp, learnedButtons.remove(code) != nil { return nil }
        if type == .otherMouseDragged, learnedButtons.contains(code) { return nil }
        if let learning, learning.deadline >= Date(), type == .otherMouseDown {
            learnedButtons.insert(code)
            self.learning = nil
            let other = learning.down ? router.config.upButton : router.config.downButton
            if code == other {
                // Swap, so either learning order works when initial guesses are reversed.
                if learning.down { router.config.upButton = router.config.downButton }
                else { router.config.downButton = router.config.upButton }
            }
            if learning.down { router.config.downButton = code } else { router.config.upButton = code }
            defaults.set(router.config.downButton, forKey: "downButton")
            defaults.set(router.config.upButton, forKey: "upButton")
            lastResult = "Learned \(learning.down ? "down" : "up") button: Quartz \(code)"
            log(lastResult)
            DispatchQueue.main.async { self.refreshMenu() }
            return nil
        }
        let input = Input(type: type, code: code, flags: event.flags,
                          repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                          vertical: event.getDoubleValueField(.scrollWheelEventDeltaAxis1),
                          horizontal: event.getDoubleValueField(.scrollWheelEventDeltaAxis2),
                          momentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0)
        let decision = router.route(input, now: ProcessInfo.processInfo.systemUptime)
        if let action = decision.action {
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            DispatchQueue.main.async { self.perform(action, pid: pid) }
        }
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }

    func perform(_ action: BindingAction, pid: pid_t?) {
        if dryRun { report("Dry run: \(action.rawValue)"); return }
        switch action {
        case .missionControl:
            let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async { self.report(error.map { "Mission Control: \($0.localizedDescription)" } ?? "Opened Mission Control") }
            }
        case .lock:
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: down) else { continue }
                event.flags = [.maskControl, .maskCommand]
                event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
                event.post(tap: .cgSessionEventTap)
            }
            report("Sent macOS Lock Screen shortcut")
        case .left, .middle, .right:
            guard let pid else { report("No frontmost app"); return }
            let screens = NSScreen.screens
            guard let first = screens.first else { report("No attached screen"); return }
            let areas = screens.map { DisplayArea(frame: accessibilityRect($0.frame, primaryTop: first.frame.maxY),
                                                  visible: accessibilityRect($0.visibleFrame, primaryTop: first.frame.maxY)) }
            let column = action == .left ? 0 : action == .middle ? 1 : 2
            worker.async {
                let result = moveWindow(pid: pid, displays: areas, column: column)
                DispatchQueue.main.async { self.report(result) }
            }
        }
    }

    func report(_ message: String) { lastResult = message; log(message); refreshMenu() }

    func item(_ title: String, _ selector: Selector? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        entry.target = self
        return entry
    }

    func refreshMenu() {
        let menu = NSMenu()
        menu.addItem(item(tap == nil ? "Waiting for macOS permission" : router.paused ? "Shortcuts paused" : "Shortcuts active"))
        menu.addItem(item(lastResult))
        menu.addItem(.separator())
        menu.addItem(item("Control + down → Left third"))
        menu.addItem(item("Command + down → Middle third"))
        menu.addItem(item("Command + up → Right third"))
        menu.addItem(item("Command + Shift + down → Left third"))
        menu.addItem(item("F6 → Mission Control · F9 → Lock"))
        menu.addItem(.separator())
        let mode = item("Use thumb buttons", #selector(buttonMode)); mode.state = router.config.mode == .buttons ? .on : .off
        menu.addItem(mode)
        let scroll = item("Use scroll wheel", #selector(scrollMode)); scroll.state = router.config.mode == .scroll ? .on : .off
        menu.addItem(scroll)
        menu.addItem(item("Learn down button (currently \(router.config.downButton))…", #selector(learnDown)))
        menu.addItem(item("Learn up button (currently \(router.config.upButton))…", #selector(learnUp)))
        menu.addItem(.separator())
        menu.addItem(item(router.paused ? "Resume shortcuts" : "Pause shortcuts", #selector(togglePause)))
        menu.addItem(item("Open Accessibility settings…", #selector(accessibilitySettings)))
        menu.addItem(item("Open Input Monitoring settings…", #selector(inputSettings)))
        menu.addItem(item("Retry permissions", #selector(retry)))
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.hegenberg.BetterTouchTool").isEmpty {
            menu.addItem(item("BetterTouchTool is running — shortcuts may conflict"))
            menu.addItem(item("Quit BetterTouchTool", #selector(quitBTT)))
        }
        menu.addItem(item("Quit MacBindings", #selector(quit)))
        statusItem.menu = menu
        statusItem.button?.title = tap == nil ? "Ⅲ!" : router.paused ? "ⅢⅡ" : "Ⅲ"
    }
    @objc func buttonMode() { router.config.mode = .buttons; defaults.set("buttons", forKey: "mouseMode"); refreshMenu() }
    @objc func scrollMode() { router.config.mode = .scroll; defaults.set("scroll", forKey: "mouseMode"); refreshMenu() }
    func learn(_ down: Bool) {
        guard tap != nil else { report("Grant permissions before learning a button."); return }
        buttonMode()
        learning = (down, Date().addingTimeInterval(15))
        report("Click the \(down ? "down" : "up") thumb button within 15 seconds.")
    }
    @objc func learnDown() { learn(true) }
    @objc func learnUp() { learn(false) }
    @objc func togglePause() { router.paused.toggle(); defaults.set(router.paused, forKey: "paused"); refreshMenu() }
    @objc func accessibilitySettings() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func inputSettings() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc func retry() { tryStart(); refreshMenu() }
    @objc func quitBTT() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.hegenberg.BetterTouchTool") { app.terminate() }
        report("Requested BetterTouchTool quit; disable its launch at login after verification.")
    }
    @objc func quit() { NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--check-access") {
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input Monitoring: \(CGPreflightListenEventAccess())")
    exit(AXIsProcessTrusted() ? 0 : 2)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MacBindings()
app.delegate = delegate
app.run()
