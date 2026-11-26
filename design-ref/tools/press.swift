// Posts a press of a single right-side modifier key, the way a real keyboard does
// (flagsChanged down with the device-specific bit, then flagsChanged up).
//
//   press right-option  [holdSeconds]   -> VoiceInk hotkey
//   press right-command [holdSeconds]   -> Spokenly hotkey
//   press check                         -> print permission status
import ApplicationServices
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let key = args.count > 1 ? args[1] : "check"

if key == "check" {
    print("accessibility(post keys)=\(AXIsProcessTrusted())")
    print("screenRecording=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}

if key == "request" {
    // Adds the responsible app to both Privacy lists and shows the system prompts.
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    print("accessibility(post keys)=\(AXIsProcessTrustedWithOptions(options))")
    print("screenRecording=\(CGRequestScreenCaptureAccess())")
    exit(0)
}

let hold = args.count > 2 ? (Double(args[2]) ?? 0.08) : 0.08

let keyCode: CGKeyCode
let flagMask: UInt64
switch key {
case "right-option":
    keyCode = 61
    flagMask = CGEventFlags.maskAlternate.rawValue | 0x40  // NX_DEVICERALTKEYMASK
case "right-command":
    keyCode = 54
    flagMask = CGEventFlags.maskCommand.rawValue | 0x10  // NX_DEVICERCMDKEYMASK
default:
    FileHandle.standardError.write("unknown key \(key)\n".data(using: .utf8)!)
    exit(2)
}

let nonCoalesced: UInt64 = 0x100  // present on real hardware events
let source = CGEventSource(stateID: .hidSystemState)

func post(down: Bool) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else {
        FileHandle.standardError.write("could not create event\n".data(using: .utf8)!)
        exit(1)
    }
    event.type = .flagsChanged
    event.flags = CGEventFlags(rawValue: down ? (flagMask | nonCoalesced) : nonCoalesced)
    event.post(tap: .cghidEventTap)
}

post(down: true)
usleep(useconds_t(hold * 1_000_000))
post(down: false)
