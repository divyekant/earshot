import CoreAudio
import Foundation

/// The default input device of the Mac (Core Audio). earshot keeps one voice profile for each microphone, because
/// the voice score and the phrase templates match best on the microphone of the enrolment (E6, D-11).
public struct InputDevice: Equatable, Sendable {
    /// The device UID. It stays the same for one microphone after a restart and after a new connection.
    public var id: String
    /// The name of the device, for example "MacBook Pro Microphone".
    public var name: String

    public init(id: String, name: String) { self.id = id; self.name = name }

    /// The default input device now, or nil if the Mac has none.
    public static var current: InputDevice? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultInputAddress
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown, let uid = text(device, kAudioDevicePropertyDeviceUID) else {
            return nil
        }
        return InputDevice(id: uid, name: text(device, kAudioObjectPropertyName) ?? uid)
    }

    static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// A text property of a device. Core Audio gives a new CFString: the caller releases it.
    private static func text(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// Calls `onChange` on the main thread when the default input device of the Mac changes.
/// Keep a reference to it. The watch stops when it goes away.
public final class InputDeviceWatcher {
    private var block: AudioObjectPropertyListenerBlock?

    public init(onChange: @escaping () -> Void) {
        var address = InputDevice.defaultInputAddress
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            self.block = block
        }
    }

    deinit {
        guard let block else { return }
        var address = InputDevice.defaultInputAddress
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }
}
