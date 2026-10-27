import CoreAudio
import Foundation

/// Captures all system audio with a Core Audio process tap (muting the original),
/// runs it through `AudioProcessor`, and plays the result on an output device.
///
/// The tap and the output device are combined in a private aggregate device, so
/// one IO callback receives the tapped audio as input and fills the device's
/// output on the same clock.
final class TapEngine {
  static let aggregateUIDPrefix = "subwave.aggregate."

  let processor: AudioProcessor
  private(set) var sampleRate: Double = 48_000
  private(set) var isRunning = false

  private var tapID = AudioObjectID(0)
  private var aggregateID = AudioObjectID(0)
  private var ioProcID: AudioDeviceIOProcID?

  init (processor: AudioProcessor) {
    self.processor = processor
  }

  deinit {
    stop()
  }

  func start (outputUID: String) throws {
    stop()
    do {
      try createTap()
      try createAggregate(outputUID: outputUID)
      try startIO(outputUID: outputUID)
      isRunning = true
    } catch {
      stop()
      throw error
    }
  }

  func stop () {
    if aggregateID != 0 {
      if let ioProcID {
        AudioDeviceStop(aggregateID, ioProcID)
        AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
      }
      AudioHardwareDestroyAggregateDevice(aggregateID)
    }
    if tapID != 0 {
      AudioHardwareDestroyProcessTap(tapID)
    }
    ioProcID = nil
    aggregateID = 0
    tapID = 0
    isRunning = false
  }

  // MARK: Setup

  private var tapUUID = UUID()

  private func createTap () throws {
    // Leave our own output out of the tap, or we'd capture what we play
    let excluded = AudioSystem.ownProcessObject.map { [$0] } ?? []
    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
    tapUUID = UUID()
    description.uuid = tapUUID
    description.name = "SubWave"
    description.isPrivate = true
    // Silence the original playback while SubWave is running; it resumes
    // automatically if SubWave quits or crashes
    description.muteBehavior = .mutedWhenTapped

    var tap = AudioObjectID(0)
    try check(AudioHardwareCreateProcessTap(description, &tap), "Couldn't create the system audio tap")
    tapID = tap
  }

  private func createAggregate (outputUID: String) throws {
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "SubWave",
      kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapUIDKey: tapUUID.uuidString,
        kAudioSubTapDriftCompensationKey: true
      ]],
      kAudioAggregateDeviceTapAutoStartKey: true
    ]
    var aggregate = AudioObjectID(0)
    try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate),
              "Couldn't create the SubWave audio device")
    aggregateID = aggregate
    sampleRate = AudioSystem.nominalSampleRate(aggregate)
  }

  private func startIO (outputUID: String) throws {
    // The output device's own inputs (e.g. an audio interface's mics) come
    // before the tap in the aggregate's input buffers; skip them
    let skipBuffers = AudioSystem.device(uid: outputUID).map {
      AudioSystem.objects($0, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count
    } ?? 0

    let processor = self.processor
    var procID: AudioDeviceIOProcID?
    try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
      Self.render(processor: processor, input: input, output: output, skipBuffers: skipBuffers)
    }, "Couldn't set up audio processing")
    ioProcID = procID
    try check(AudioDeviceStart(aggregateID, procID), "Couldn't start audio processing")
  }

  // MARK: Audio thread

  private struct Channels {
    var left: UnsafeMutablePointer<Float>
    var right: UnsafeMutablePointer<Float>?
    var stride: Int
    var frames: Int
  }

  /// Finds the first stereo (or mono) pair in a buffer list, interleaved or not.
  private static func channels (_ list: UnsafeMutableAudioBufferListPointer, from index: Int) -> Channels? {
    guard index < list.count, let data = list[index].mData?.assumingMemoryBound(to: Float.self) else { return nil }
    let buffer = list[index]
    let count = Int(max(1, buffer.mNumberChannels))
    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * count)
    if count >= 2 {
      return Channels(left: data, right: data + 1, stride: count, frames: frames)
    }
    let right = index + 1 < list.count ? list[index + 1].mData?.assumingMemoryBound(to: Float.self) : nil
    return Channels(left: data, right: right, stride: 1, frames: frames)
  }

  private static func render (processor: AudioProcessor,
                              input: UnsafePointer<AudioBufferList>,
                              output: UnsafeMutablePointer<AudioBufferList>,
                              skipBuffers: Int) {
    let outputList = UnsafeMutableAudioBufferListPointer(output)
    for buffer in outputList where buffer.mData != nil {
      memset(buffer.mData, 0, Int(buffer.mDataByteSize))
    }

    let inputList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    guard let source = channels(inputList, from: skipBuffers),
          let destination = channels(outputList, from: 0) else { return }

    let frames = min(source.frames, destination.frames)
    for i in 0..<frames {
      var left = source.left[i * source.stride]
      var right = source.right?[i * source.stride] ?? left
      processor.process(left: &left, right: &right)
      processor.meter.add(left: left, right: right)
      if let outRight = destination.right {
        destination.left[i * destination.stride] = left
        outRight[i * destination.stride] = right
      } else {
        destination.left[i * destination.stride] = (left + right) / 2
      }
    }
  }
}
