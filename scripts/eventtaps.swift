import CoreGraphics
let pid = pid_t(CommandLine.arguments[1])!
var n: UInt32 = 0
CGGetEventTapList(0, nil, &n)
var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(n))
CGGetEventTapList(n, &list, &n)
let mine = list.filter { $0.tappingProcess == pid && $0.enabled }
print("aktive Event-Taps von Tippi: \(mine.count)"); for t in mine { print("  Tap \(t.eventTapID) Maske 0x\(String(t.eventsOfInterest, radix: 16)) nurLesen=\(t.options == .listenOnly)") }
