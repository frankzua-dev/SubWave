import CoreAudio
import Foundation

struct AudioError: Error, CustomStringConvertible {
  let description: String

  init (_ message: String, _ status: OSStatus? = nil) {
    description = status.map { "\(message) (OSStatus \($0))" } ?? message
  }
}

@discardableResult
func check (_ status: OSStatus, _ message: String) throws -> OSStatus {
  if status != noErr { throw AudioError(message, status) }
  return status
}

struct OutputDevice: Identifiable, Hashable {
  let id: AudioObjectID
  let uid: String
  let name: String
  let transport: UInt32

  var symbol: String {
    switch transport {
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
    case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
    case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
    case kAudioDeviceTransportTypeUSB: return "cable.connector"
    default: return "speaker.wave.2.fill"
    }
  }
}

/// Thin, typed access to the Core Audio object model.
enum AudioSystem {
  static let system = AudioObjectID(kAudioObjectSystemObject)

  static func address (_ selector: AudioObjectPropertySelector,
                       _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                       _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }

  static func property<T> (_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, default value: T) -> T? {
    var address = address
    var result = value
    var size = UInt32(MemoryLayout<T>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result)
    return status == noErr ? result : nil
  }

  static func string (_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
  }

  static func objects (_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
    var address = address(selector, scope)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
  }

  // MARK: Devices

  static var defaultOutputDeviceID: AudioObjectID? {
    property(system, address(kAudioHardwarePropertyDefaultOutputDevice), default: AudioObjectID(0)).flatMap { $0 == 0 ? nil : $0 }
  }

  static func device (uid: String) -> AudioObjectID? {
    outputDevices().first { $0.uid == uid }?.id
  }

  static func outputDevices () -> [OutputDevice] {
    objects(system, kAudioHardwarePropertyDevices).compactMap { id in
      guard !objects(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).isEmpty,
            let uid = string(id, kAudioDevicePropertyDeviceUID),
            !uid.hasPrefix(TapEngine.aggregateUIDPrefix),
            let name = string(id, kAudioObjectPropertyName) else { return nil }
      if property(id, address(kAudioDevicePropertyIsHidden), default: UInt32(0)) == 1 { return nil }
      let transport = property(id, address(kAudioDevicePropertyTransportType), default: UInt32(0)) ?? 0
      // Aggregate devices made by other apps can't be nested inside ours
      if transport == kAudioDeviceTransportTypeAggregate { return nil }
      return OutputDevice(id: id, uid: uid, name: name, transport: transport)
    }
  }

  static func nominalSampleRate (_ device: AudioObjectID) -> Double {
    property(device, address(kAudioDevicePropertyNominalSampleRate), default: Float64(0)) ?? 48_000
  }

  // MARK: Hardware volume (output scope; main element or left/right channels)

  private static func volumeElements (_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
    for elements in [[kAudioObjectPropertyElementMain], [1, 2]] as [[AudioObjectPropertyElement]] {
      if elements.allSatisfy({ element in
        var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
          && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
      }) {
        return elements
      }
    }
    return []
  }

  static func hasVolume (_ device: AudioObjectID) -> Bool {
    !volumeElements(device).isEmpty
  }

  static func volume (_ device: AudioObjectID) -> Float? {
    let values = volumeElements(device).compactMap {
      property(device, address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, $0), default: Float32(0))
    }
    return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
  }

  static func setVolume (_ device: AudioObjectID, _ volume: Float) {
    var value = Float32(min(1, max(0, volume)))
    for element in volumeElements(device) {
      var address = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element)
      AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
  }

  // MARK: Processes

  static var ownProcessObject: AudioObjectID? {
    var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var pid = ProcessInfo.processInfo.processIdentifier
    var object = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
    return status == noErr && object != 0 ? object : nil
  }

  // MARK: Listeners

  /// Calls `handler` on the main queue whenever the property changes. Keep the token to stay subscribed.
  static func listen (_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ handler: @escaping () -> Void) -> ListenerToken {
    ListenerToken(object: object, address: address, handler: handler)
  }

  final class ListenerToken {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    fileprivate init (object: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping () -> Void) {
      self.object = object
      self.address = address
      self.block = { _, _ in handler() }
      AudioObjectAddPropertyListenerBlock(object, &self.address, .main, block)
    }

    deinit {
      AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
    }
  }
}
