import CoreAudio
import Foundation

/// Mutes/unmutes the current default system audio **output** device via
/// CoreAudio. Used by `AudioRecorder` to optionally silence system audio
/// while Tippi records (dictation, popup mic, translate panel) so playing
/// media doesn't leak into the recording or distract while speaking.
///
/// Best-effort by design: some output devices (certain USB/Bluetooth
/// interfaces, some aggregate devices) expose no mute control at all.
/// Every call fails soft (returns `nil`/`false`) instead of throwing —
/// muting system audio is a convenience, never a precondition for
/// recording to work.
enum SystemAudioMuter {
    /// Current mute state of the default output device, or `nil` if the
    /// device has no mute control (or none could be resolved).
    static func isMuted() -> Bool? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        var address = muteAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        guard status == noErr else { return nil }
        return muted != 0
    }

    /// Sets the default output device's mute state. Returns whether the
    /// write actually happened — `false` means the device has no mute
    /// control or the write failed; callers should treat that as "nothing
    /// to restore later", not as an error to surface to the user.
    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let deviceID = defaultOutputDevice() else { return false }
        var address = muteAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        return status == noErr
    }

    // MARK: - Private

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
