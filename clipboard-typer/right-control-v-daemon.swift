#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

private let toolName = "right-control-v-daemon"
private let vKeyCode: Int64 = 9
private let controlMask: UInt64 = 0x00040000
private let shiftMask: UInt64 = 0x00020000
private let optionMask: UInt64 = 0x00080000
private let commandMask: UInt64 = 0x00100000
private let rightControlMask: UInt64 = 0x00002000

final class HotkeyDaemon {
    private let initialDelay: TimeInterval
    private let chunkDelay: useconds_t
    private let chunkSize: Int
    private let verbose: Bool
    private let workQueue = DispatchQueue(label: toolName)
    private var isTyping = false

    init(initialDelay: TimeInterval, chunkDelay: TimeInterval, chunkSize: Int, verbose: Bool) {
        self.initialDelay = initialDelay
        self.chunkDelay = useconds_t(chunkDelay * 1_000_000)
        self.chunkSize = chunkSize
        self.verbose = verbose
    }

    func start() -> Never {
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            fputs("""
            Keyboard listen access is not granted.
            Add the app/process that runs this daemon to System Settings > Privacy & Security > Input Monitoring, then restart it.

            """, stderr)
            exit(2)
        }

        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            fputs("""
            Keyboard event post access is not granted.
            Add the app/process that runs this daemon to System Settings > Privacy & Security > Accessibility, then restart it.

            """, stderr)
            exit(2)
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventCallback,
            userInfo: selfPointer
        ) else {
            fputs("Could not create keyboard event tap. Check Input Monitoring and Accessibility permissions.\n", stderr)
            exit(2)
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("\(toolName): listening for Right Control+V")
        fflush(stdout)

        CFRunLoopRun()
        exit(0)
    }

    func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return Unmanaged.passUnretained(event)
        }

        guard isRightControlV(event) else {
            return Unmanaged.passUnretained(event)
        }

        workQueue.async { [weak self] in
            self?.typeClipboardIfIdle()
        }

        return nil
    }

    private func isRightControlV(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == vKeyCode else {
            return false
        }

        return Self.matchesRightControlV(rawFlags: event.flags.rawValue)
    }

    static func matchesRightControlV(rawFlags: UInt64) -> Bool {
        let requiredMask = controlMask | rightControlMask
        let disallowedMask = commandMask | optionMask | shiftMask

        return (rawFlags & requiredMask) == requiredMask
            && (rawFlags & disallowedMask) == 0
    }

    private func typeClipboardIfIdle() {
        guard !isTyping else {
            return
        }

        isTyping = true
        defer { isTyping = false }

        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            log("clipboard does not contain text")
            return
        }

        guard !clipboardText.isEmpty else {
            log("clipboard is empty")
            return
        }

        Thread.sleep(forTimeInterval: initialDelay)
        postUnicodeText(clipboardText)
    }

    private func postUnicodeText(_ text: String) {
        let utf16 = Array<UniChar>(text.utf16)
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0

        var index = 0
        while index < utf16.count {
            let end = min(index + chunkSize, utf16.count)
            let chunk = Array(utf16[index..<end])

            chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress,
                      let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    fputs("Could not create keyboard event.\n", stderr)
                    return
                }

                keyDown.flags = []
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyDown.post(tap: .cghidEventTap)

                keyUp.flags = []
                keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                keyUp.post(tap: .cghidEventTap)
            }

            if chunkDelay > 0 {
                usleep(chunkDelay)
            }

            index = end
        }

        log("typed \(text.count) characters")
    }

    private func log(_ message: String) {
        guard verbose else {
            return
        }

        print("\(toolName): \(message)")
        fflush(stdout)
    }
}

private func usage() {
    print("""
    Usage: \(toolName) [--check-access] [--match-test] [--verbose]

    Runs a native macOS event-tap listener for Right Control+V and types the
    current clipboard text as synthetic Unicode keyboard input.

    Options:
      --check-access   Check Input Monitoring and Accessibility permissions.
      --match-test     Verify raw-flag matching for Right Control+V vs Command+V.
      --verbose        Print trigger/status messages while running.
      -h, --help       Show this help.

    Environment:
      SEND_KEYS_INITIAL_DELAY  Seconds to wait after the trigger. Default: 0.15
      SEND_KEYS_CHUNK_SIZE     UTF-16 code units per event. Default: 64
      SEND_KEYS_CHUNK_DELAY    Seconds between chunks. Default: 0.02
    """)
}

private func envDouble(_ name: String, default defaultValue: Double) -> Double {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Double(raw),
          value >= 0 else {
        return defaultValue
    }
    return value
}

private func envInt(_ name: String, default defaultValue: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Int(raw),
          value > 0 else {
        return defaultValue
    }
    return value
}

private let args = Array(CommandLine.arguments.dropFirst())
private let knownArgs = Set(["--check-access", "--match-test", "--verbose", "-h", "--help"])
private let unknownArgs = args.filter { !knownArgs.contains($0) }

if !unknownArgs.isEmpty {
    fputs("Unknown argument: \(unknownArgs.joined(separator: " "))\n", stderr)
    usage()
    exit(64)
}

if args.contains("-h") || args.contains("--help") {
    usage()
    exit(0)
}

if args.contains("--check-access") {
    let canListen = CGPreflightListenEventAccess()
    let canPost = CGPreflightPostEventAccess()
    print("keyboard listen access: \(canListen ? "granted" : "not granted")")
    print("keyboard event access: \(canPost ? "granted" : "not granted")")
    exit(canListen && canPost ? 0 : 2)
}

if args.contains("--match-test") {
    let samples: [(String, UInt64, Bool)] = [
        ("observed Right Control", 0x00042100, true),
        ("Right Control synthetic", controlMask | rightControlMask, true),
        ("Right Command typical", commandMask | 0x00000110, false),
        ("Left Command typical", commandMask | 0x00000108, false),
        ("plain V", 0x00000000, false)
    ]

    var failed = false
    for (name, rawFlags, expected) in samples {
        let actual = HotkeyDaemon.matchesRightControlV(rawFlags: rawFlags)
        print("\(name): rawFlags=\(String(format: "0x%016llx", rawFlags)) match=\(actual)")
        if actual != expected {
            failed = true
        }
    }

    exit(failed ? 1 : 0)
}

private func eventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown, let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let daemon = Unmanaged<HotkeyDaemon>.fromOpaque(refcon).takeUnretainedValue()
    return daemon.handle(event: event)
}

let daemon = HotkeyDaemon(
    initialDelay: envDouble("SEND_KEYS_INITIAL_DELAY", default: 0.15),
    chunkDelay: envDouble("SEND_KEYS_CHUNK_DELAY", default: 0.02),
    chunkSize: envInt("SEND_KEYS_CHUNK_SIZE", default: 64),
    verbose: args.contains("--verbose")
)

daemon.start()
