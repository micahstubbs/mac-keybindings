#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

let toolName = "type-clipboard"

func usage() {
    print("""
    Usage: \(toolName) [--dry-run] [--check-access]

    Sends the current macOS clipboard text as synthetic keyboard text input.

    Options:
      --dry-run        Read clipboard text and report what would be typed.
      --check-access   Check whether this process can post keyboard events.
      -h, --help       Show this help.

    Environment:
      SEND_KEYS_INITIAL_DELAY  Seconds to wait before typing. Default: 0.15
      SEND_KEYS_CHUNK_SIZE     UTF-16 code units per event. Default: 64
      SEND_KEYS_CHUNK_DELAY    Seconds between chunks. Default: 0.02
    """)
}

func envDouble(_ name: String, default defaultValue: Double) -> Double {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Double(raw),
          value >= 0 else {
        return defaultValue
    }
    return value
}

func envInt(_ name: String, default defaultValue: Int) -> Int {
    guard let raw = ProcessInfo.processInfo.environment[name],
          let value = Int(raw),
          value > 0 else {
        return defaultValue
    }
    return value
}

let args = Array(CommandLine.arguments.dropFirst())
let knownArgs = Set(["--dry-run", "--check-access", "-h", "--help"])
let unknownArgs = args.filter { !knownArgs.contains($0) }

if !unknownArgs.isEmpty {
    fputs("Unknown argument: \(unknownArgs.joined(separator: " "))\n", stderr)
    usage()
    exit(64)
}

if args.contains("-h") || args.contains("--help") {
    usage()
    exit(0)
}

let dryRun = args.contains("--dry-run")
let checkAccess = args.contains("--check-access")
let initialDelay = envDouble("SEND_KEYS_INITIAL_DELAY", default: 0.15)
let chunkDelay = envDouble("SEND_KEYS_CHUNK_DELAY", default: 0.02)
let chunkSize = envInt("SEND_KEYS_CHUNK_SIZE", default: 64)

let canPostEvents = CGPreflightPostEventAccess()

if checkAccess {
    print(canPostEvents ? "keyboard event access: granted" : "keyboard event access: not granted")
    exit(canPostEvents ? 0 : 2)
}

guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
    fputs("Clipboard does not contain text.\n", stderr)
    exit(1)
}

guard !clipboardText.isEmpty else {
    fputs("Clipboard is empty.\n", stderr)
    exit(0)
}

let utf16 = Array<UniChar>(clipboardText.utf16)

if dryRun {
    print("clipboard characters: \(clipboardText.count)")
    print("utf16 code units: \(utf16.count)")
    print("chunk size: \(chunkSize)")
    print("chunks: \((utf16.count + chunkSize - 1) / chunkSize)")
    exit(0)
}

if !canPostEvents {
    _ = CGRequestPostEventAccess()
    fputs("""
    Keyboard event access is not granted.
    Add the app that runs this script to System Settings > Privacy & Security > Accessibility, then retry.

    """, stderr)
    exit(2)
}

Thread.sleep(forTimeInterval: initialDelay)

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
            exit(1)
        }

        keyDown.flags = []
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        keyDown.post(tap: .cghidEventTap)

        keyUp.flags = []
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        keyUp.post(tap: .cghidEventTap)
    }

    if chunkDelay > 0 {
        usleep(useconds_t(chunkDelay * 1_000_000))
    }

    index = end
}
