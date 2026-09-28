import AppKit

// Only these four modifiers participate; Caps Lock, Fn and device-specific bits do not.
let shortcutModifiers: CGEventFlags = [.maskControl, .maskCommand, .maskShift, .maskAlternate]
let syntheticMarker: Int64 = 0x4D414342
// Default bundle identifier; the installer can override it with MACBINDINGS_BUNDLE_ID.
let defaultBundleIdentifier = "io.github.micahstubbs.macbindings"

enum BindingAction: String { case left, middle, right, missionControl, lock }
enum MouseMode: String { case buttons, scroll }

struct BindingConfig {
    var mode: MouseMode = .buttons
    var downButton: Int64 = 3 // Quartz is zero-based; learn actual hardware in the menu.
    var upButton: Int64 = 4
}

struct Input {
    var type: CGEventType
    var code: Int64 = 0
    var flags: CGEventFlags = []
    var repeatKey = false
    var vertical: Double = 0
    var horizontal: Double = 0
    var momentum = false
    var synthetic = false
}

struct Decision {
    var consume = false
    var action: BindingAction? = nil
}

// Stateful pairing prevents swallowed presses leaking unmatched releases to applications.
struct BindingRouter {
    var config = BindingConfig()
    var paused = false
    var keys = Set<Int64>()
    var buttons = Set<Int64>()
    var lastScroll: (BindingAction, TimeInterval)?

    mutating func route(_ input: Input, now: TimeInterval) -> Decision {
        if input.synthetic { return Decision() }
        if input.type == .keyUp, keys.remove(input.code) != nil { return Decision(consume: true) }
        if input.type == .otherMouseUp, buttons.remove(input.code) != nil { return Decision(consume: true) }
        if input.type == .otherMouseDragged, buttons.contains(input.code) { return Decision(consume: true) }
        if input.type == .keyDown, keys.contains(input.code) { return Decision(consume: true) }
        if input.type == .otherMouseDown, buttons.contains(input.code) { return Decision(consume: true) }
        guard !paused else { return Decision() }
        let mods = input.flags.intersection(shortcutModifiers)
        if input.type == .keyDown, mods.isEmpty, !input.repeatKey {
            let action: BindingAction? = input.code == 97 ? .missionControl : input.code == 101 ? .lock : nil
            if let action { keys.insert(input.code); return Decision(consume: true, action: action) }
        }
        var down: Bool?
        if config.mode == .buttons, input.type == .otherMouseDown {
            if input.code == config.downButton { down = true }
            else if input.code == config.upButton { down = false }
        } else if config.mode == .scroll, input.type == .scrollWheel,
                  input.vertical != 0, abs(input.vertical) > abs(input.horizontal) {
            down = input.vertical < 0
        }
        guard let down else { return Decision() }
        let action: BindingAction?
        if down && (mods == .maskControl || mods == [.maskCommand, .maskShift]) { action = .left }
        else if mods == .maskCommand { action = down ? .middle : .right }
        else { action = nil }
        guard let action else { return Decision() }
        if input.type == .otherMouseDown { buttons.insert(input.code) }
        if input.type == .scrollWheel {
            if input.momentum { return Decision(consume: true) }
            if let lastScroll, lastScroll.0 == action, now - lastScroll.1 < 0.25 {
                return Decision(consume: true)
            }
            lastScroll = (action, now)
        }
        return Decision(consume: true, action: action)
    }
}

struct DisplayArea {
    var frame: CGRect
    var visible: CGRect
}

func accessibilityRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
}

func targetThird(window: CGRect, displays: [DisplayArea], column: Int) -> CGRect? {
    guard (0...2).contains(column), !displays.isEmpty else { return nil }
    // The display with the largest window overlap wins, including monitors left/above primary.
    let display = displays.max { a, b in
        func score(_ display: DisplayArea) -> CGFloat {
            let intersection = window.intersection(display.frame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        return score(a) < score(b)
    }!
    let area = display.visible
    let start = (area.width * CGFloat(column) / 3).rounded()
    let end = (area.width * CGFloat(column + 1) / 3).rounded()
    return CGRect(x: area.minX + start, y: area.minY, width: end - start, height: area.height)
}
