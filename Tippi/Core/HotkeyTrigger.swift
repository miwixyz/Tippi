import Foundation

enum ModifierKey: String, Codable, CaseIterable, Identifiable, Equatable {
    case leftShift
    case rightShift
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand

    var id: String { rawValue }

    /// macOS virtual key code (kVK_*)
    var keyCode: UInt16 {
        switch self {
        case .leftCommand:  return 0x37  // 55
        case .leftShift:    return 0x38  // 56
        case .leftOption:   return 0x3A  // 58
        case .leftControl:  return 0x3B  // 59
        case .rightCommand: return 0x36  // 54
        case .rightShift:   return 0x3C  // 60
        case .rightOption:  return 0x3D  // 61
        case .rightControl: return 0x3E  // 62
        }
    }

    var displayName: String {
        switch self {
        case .leftShift:    return "Left Shift"
        case .rightShift:   return "Right Shift"
        case .leftControl:  return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption:   return "Left Option"
        case .rightOption:  return "Right Option"
        case .leftCommand:  return "Left Command"
        case .rightCommand: return "Right Command"
        }
    }
}

enum HotkeyTrigger: Codable, Equatable {
    case doubleTap(modifier: ModifierKey, thresholdMs: Int)
    case hold(modifier: ModifierKey, durationMs: Int)
    case combo(keyCode: UInt32, carbonModifierFlags: UInt32)

    static let `default`: HotkeyTrigger = .doubleTap(modifier: .rightOption, thresholdMs: 300)

    var summary: String {
        switch self {
        case .doubleTap(let mod, _):
            return "Double-tap \(mod.displayName)"
        case .hold(let mod, let ms):
            return "Hold \(mod.displayName) for \(ms) ms"
        case .combo:
            return "Custom key combo"
        }
    }
}
