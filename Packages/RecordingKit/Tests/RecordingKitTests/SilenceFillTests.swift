import TestKit
import CoreMedia
import AudioToolbox
@testable import RecordingKit

/// An LPCM CMSampleBuffer holding `samples` (per channel) filled with `fill`.
/// Interleaved int16 or non-interleaved float32 — the two shapes the recorder sees
/// (SCK system audio and AVCaptureAudioDataOutput mics are float32 non-interleaved).
private func makePCMBuffer(float: Bool, channels: UInt32, samples: Int, fill: UInt8,
                           pts: CMTime = CMTime(value: 4_800, timescale: 48_000)) -> CMSampleBuffer? {
    let bytesPerSample: UInt32 = float ? 4 : 2
    let flags = float
        ? kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved
        : kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    let bytesPerFrame = float ? bytesPerSample : bytesPerSample * channels
    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
        mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
        mChannelsPerFrame: channels, mBitsPerChannel: bytesPerSample * 8, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                   formatDescriptionOut: &format)
    let length = samples * Int(bytesPerSample * channels)
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: length,
                                       blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                       dataLength: length, flags: kCMBlockBufferAssureMemoryNowFlag,
                                       blockBufferOut: &block)
    guard let format, let block else { return nil }
    CMBlockBufferFillDataBytes(with: CChar(bitPattern: fill), blockBuffer: block, offsetIntoDestination: 0, dataLength: length)
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: samples,
        presentationTimeStamp: pts, packetDescriptions: nil, sampleBufferOut: &sample)
    return sample
}

/// Every byte of every AudioBuffer in `buffer`, read the way AVAssetWriter sees them.
private func pcmBytes(_ buffer: CMSampleBuffer) -> [[UInt8]] {
    var sizeNeeded = 0
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        buffer, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil, bufferListSize: 0,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
    let raw = UnsafeMutableRawPointer.allocate(byteCount: sizeNeeded,
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    var retained: CMBlockBuffer?
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: sizeNeeded,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
        blockBufferOut: &retained) == noErr else { return [] }
    return UnsafeMutableAudioBufferListPointer(list).map { b in
        guard let data = b.mData else { return [] }
        return Array(UnsafeRawBufferPointer(start: data, count: Int(b.mDataByteSize)))
    }
}

private func asbd(float: Bool = false, signed: Bool = false, bits: UInt32,
                  bigEndian: Bool = false, id: AudioFormatID = kAudioFormatLinearPCM) -> AudioStreamBasicDescription {
    var flags: AudioFormatFlags = kAudioFormatFlagIsPacked
    if float { flags |= kAudioFormatFlagIsFloat }
    if signed { flags |= kAudioFormatFlagIsSignedInteger }
    if bigEndian { flags |= kAudioFormatFlagIsBigEndian }
    return AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: id, mFormatFlags: flags,
                                       mBytesPerPacket: bits / 8, mFramesPerPacket: 1,
                                       mBytesPerFrame: bits / 8, mChannelsPerFrame: 1,
                                       mBitsPerChannel: bits, mReserved: 0)
}

let silenceFillTests: [TestCase] = [
    TestCase("silenceIsAllZeroBytesForFloatAndSignedPCM") { t in
        t.equal(SilenceFill.silentSample(for: asbd(float: true, bits: 32)), [0, 0, 0, 0])
        t.equal(SilenceFill.silentSample(for: asbd(float: true, bits: 64)), [UInt8](repeating: 0, count: 8))
        t.equal(SilenceFill.silentSample(for: asbd(signed: true, bits: 16)), [0, 0])
        t.equal(SilenceFill.silentSample(for: asbd(signed: true, bits: 24)), [0, 0, 0])
    },
    TestCase("silenceIsTheMidpointForUnsignedPCM") { t in
        t.equal(SilenceFill.silentSample(for: asbd(bits: 8)), [0x80])
        t.equal(SilenceFill.silentSample(for: asbd(bits: 16)), [0x00, 0x80], "little-endian 0x8000")
        t.equal(SilenceFill.silentSample(for: asbd(bits: 16, bigEndian: true)), [0x80, 0x00])
    },
    TestCase("compressedAudioHasNoSilentSample") { t in
        t.isNil(SilenceFill.silentSample(for: asbd(signed: true, bits: 16, id: kAudioFormatMPEG4AAC)))
        t.isNil(SilenceFill.silentSample(for: asbd(signed: true, bits: 0)), "no sample width")
    },
    TestCase("fillRepeatsThePatternOverTheWholeBuffer") { t in
        var bytes = [UInt8](repeating: 0x55, count: 6)
        bytes.withUnsafeMutableBytes { SilenceFill.fill($0, with: [0x00, 0x80]) }
        t.equal(bytes, [0x00, 0x80, 0x00, 0x80, 0x00, 0x80])
    },
    TestCase("silentCopyZeroesInterleavedInt16") { t in
        guard let loud = t.unwrap(makePCMBuffer(float: false, channels: 2, samples: 480, fill: 0x7F)),
              let quiet = t.unwrap(SilenceFill.silentCopy(of: loud)) else { return }
        let out = pcmBytes(quiet)
        t.equal(out.count, 1, "interleaved: one AudioBuffer")
        t.equal(out.first?.count, 480 * 2 * 2)
        t.isTrue(out.allSatisfy { $0.allSatisfy { $0 == 0 } }, "all samples silent")
    },
    TestCase("silentCopyZeroesEveryChannelOfNonInterleavedFloat32") { t in
        // The SCK system-audio shape: 48 kHz stereo float32, one buffer per channel.
        guard let loud = t.unwrap(makePCMBuffer(float: true, channels: 2, samples: 960, fill: 0x3F)),
              let quiet = t.unwrap(SilenceFill.silentCopy(of: loud)) else { return }
        let out = pcmBytes(quiet)
        t.equal(out.count, 2, "non-interleaved: one AudioBuffer per channel")
        t.equal(out.map(\.count), [960 * 4, 960 * 4])
        t.isTrue(out.allSatisfy { $0.allSatisfy { $0 == 0 } }, "all samples silent")
    },
    TestCase("silentCopyKeepsTimingFormatAndLeavesTheOriginalAlone") { t in
        let pts = CMTime(value: 96_000, timescale: 48_000)
        guard let loud = t.unwrap(makePCMBuffer(float: true, channels: 1, samples: 320, fill: 0x3F, pts: pts)),
              let quiet = t.unwrap(SilenceFill.silentCopy(of: loud)) else { return }
        t.isTrue(quiet.presentationTimeStamp == pts, "same PTS")
        t.isTrue(quiet.duration == loud.duration, "same duration")
        t.equal(quiet.numSamples, 320)
        t.isTrue(CMFormatDescriptionEqual(quiet.formatDescription, otherFormatDescription: loud.formatDescription))
        t.isTrue(pcmBytes(loud).allSatisfy { $0.allSatisfy { $0 == 0x3F } }, "source samples untouched")
    },
]
