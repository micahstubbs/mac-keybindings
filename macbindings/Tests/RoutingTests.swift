import AppKit

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { fputs("FAIL: \(name)\n", stderr); exit(1) }
    print("PASS: \(name)")
}
func route(_ input: Input, config: BindingConfig = BindingConfig()) -> Decision {
    var router = BindingRouter(config: config)
    return router.route(input, now: 1)
}
for (flags, button, action) in [(CGEventFlags.maskControl, Int64(3), BindingAction.left),
                                (.maskCommand, 3, .middle), (.maskCommand, 4, .right),
                                ([.maskCommand, .maskShift], 3, .left)] {
    let result = route(Input(type: .otherMouseDown, code: button, flags: flags))
    check(result.consume && result.action == action, "binding \(flags.rawValue)/\(button) → \(action)")
}
check(!route(Input(type: .otherMouseDown, code: 3)).consume, "unmodified thumb button passes through")
check(!route(Input(type: .otherMouseDown, code: 3, flags: [.maskCommand, .maskAlternate])).consume, "extra modifiers pass through")
check(!route(Input(type: .leftMouseDown, code: 0, flags: .maskCommand)).consume, "ordinary mouse click passes through")
check(!route(Input(type: .otherMouseDown, code: 5, flags: .maskCommand)).consume, "unconfigured button passes through")
check(route(Input(type: .otherMouseDown, code: 5, flags: .maskCommand), config: BindingConfig(downButton: 5, upButton: 6)).action == .middle, "learned hardware IDs")
var paired = BindingRouter()
_ = paired.route(Input(type: .otherMouseDown, code: 3, flags: .maskCommand), now: 1)
check(paired.route(Input(type: .otherMouseDragged, code: 3), now: 1.1).consume, "matched mouse drag consumed")
paired.paused = true
check(paired.route(Input(type: .otherMouseUp, code: 3), now: 2).consume, "release consumed even after modifier release and pause")
check(!paired.route(Input(type: .otherMouseUp, code: 4), now: 3).consume, "unmatched release passes through")
check(!paired.route(Input(type: .keyDown, code: 97), now: 4).consume, "pause passes new shortcut through")
var keyboard = BindingRouter()
check(keyboard.route(Input(type: .keyDown, code: 101, flags: [.maskSecondaryFn, .maskAlphaShift]), now: 1).action == .lock, "F9 ignores Fn and Caps Lock")
check(keyboard.route(Input(type: .keyDown, code: 101, repeatKey: true), now: 2).action == nil, "held F9 cannot retrigger lock")
check(keyboard.route(Input(type: .keyUp, code: 101, flags: .maskCommand), now: 3).consume, "F9 release remains paired")
check(route(Input(type: .keyDown, code: 97)).action == .missionControl, "F6 Mission Control")
check(!route(Input(type: .keyDown, code: 97, flags: .maskCommand)).consume, "modified F6 passes through")
check(!route(Input(type: .keyDown, code: 12, flags: [.maskControl, .maskCommand], synthetic: true)).consume, "injected lock shortcut bypasses routing")
check(!route(Input(type: .scrollWheel, flags: .maskCommand, vertical: -1)).consume, "wheel is untouched in thumb mode")
var scrolling = BindingRouter(config: BindingConfig(mode: .scroll))
check(scrolling.route(Input(type: .scrollWheel, flags: .maskCommand, vertical: -1), now: 1).action == .middle, "optional scroll down")
check(scrolling.route(Input(type: .scrollWheel, flags: .maskCommand, vertical: -1), now: 1.1).action == nil, "scroll debounce")
check(scrolling.route(Input(type: .scrollWheel, flags: .maskCommand, vertical: 1), now: 1.2).action == .right, "scroll direction change")
check(scrolling.route(Input(type: .scrollWheel, flags: .maskCommand, vertical: 1, momentum: true), now: 2).action == nil, "momentum cannot trigger")
let display = DisplayArea(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visible: CGRect(x: 0, y: 38, width: 1512, height: 874))
let rects = (0...2).map { targetThird(window: display.frame, displays: [display], column: $0)! }
check(rects[0] == CGRect(x: 0, y: 38, width: 504, height: 874), "left third excludes Dock and menu")
check(rects[1].minX == 504 && rects[2].maxX == 1512, "middle/right exact edges")
let odd = DisplayArea(frame: display.frame, visible: CGRect(x: -1920, y: -300, width: 1919, height: 1000))
let thirds = (0...2).map { targetThird(window: display.frame, displays: [odd], column: $0)! }
check(thirds[0].maxX == thirds[1].minX && thirds[1].maxX == thirds[2].minX && thirds[2].maxX == -1, "odd width has no gaps or overlap")
let left = DisplayArea(frame: CGRect(x: -1920, y: -300, width: 1920, height: 1080), visible: CGRect(x: -1920, y: -275, width: 1920, height: 1000))
check(targetThird(window: CGRect(x: -1800, y: -200, width: 1000, height: 800), displays: [display, left], column: 1)?.minX == -1280, "window selects external display with negative coordinates")
check(targetThird(window: CGRect(x: -200, y: 50, width: 1000, height: 800), displays: [display, left], column: 0)?.minX == 0, "spanning window selects greatest overlap")
check(accessibilityRect(CGRect(x: -1920, y: 982, width: 1920, height: 1080), primaryTop: 982).minY == -1080, "AppKit to AX conversion supports display above primary")
check(targetThird(window: .zero, displays: [], column: 0) == nil, "no displays is safe")
check(targetThird(window: .zero, displays: [display], column: 3) == nil, "invalid third is safe")
print("\(checks) checks passed")
