import CoreMedia
import AudioToolbox

/// Live mute: a muted source keeps appending buffers, but with silent PCM, so its
/// audio track stays continuous and in sync (dropping buffers would leave gaps
/// some players mishandle). Works on any linear-PCM layout — SCK system audio and
/// AVCaptureAudioDataOutput mics both deliver float32 non-interleaved — because
/// every sample in a buffer shares one width, so the whole block is one repeating
/// silent sample regardless of channel interleaving.
public enum SilenceFill {
    /// The bytes of one silent sample of `format`, or nil when it isn't linear PCM.
    /// Float and signed-integer silence is all zero bytes; unsigned-integer silence
    /// is the midpoint (0x80 for 8-bit, 0x8000 for 16-bit, …) in the format's byte order.
    public static func silentSample(for format: AudioStreamBasicDescription) -> [UInt8]? {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel >= 8 else { return nil }
        let width = Int(format.mBitsPerChannel + 7) / 8
        var sample = [UInt8](repeating: 0, count: width)
        let flags = format.mFormatFlags
        if flags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsSignedInteger) == 0 {
            sample[flags & kAudioFormatFlagIsBigEndian != 0 ? 0 : width - 1] = 0x80
        }
        return sample
    }

    /// Fills `bytes` with `sample` repeated from offset 0.
    public static func fill(_ bytes: UnsafeMutableRawBufferPointer, with sample: [UInt8]) {
        guard !sample.isEmpty else { return }
        for i in 0..<bytes.count { bytes[i] = sample[i % sample.count] }
    }

    /// A copy of `buffer` — same format, sample count and timing — whose samples
    /// are all silent. The source buffer is never written (its memory belongs to
    /// the capture framework). Nil when `buffer` isn't linear PCM.
    public static func silentCopy(of buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              let sample = silentSample(for: asbd),
              let source = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        let length = CMBlockBufferGetDataLength(source)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil,
                customBlockSource: nil, offsetToData: 0, dataLength: length,
                flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr,
              let block else { return nil }
        var data: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: nil, dataPointerOut: &data) == noErr,
              let data else { return nil }
        fill(UnsafeMutableRawBufferPointer(start: data, count: length), with: sample)
        var out: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block, formatDescription: format,
                sampleCount: CMSampleBufferGetNumSamples(buffer),
                presentationTimeStamp: buffer.presentationTimeStamp,
                packetDescriptions: nil, sampleBufferOut: &out) == noErr else { return nil }
        return out
    }
}
