//
//  PlayingAudioRecorder.swift
//  SpeechToTextV1
//
//  Created by Seiya Shimokawa on 4/15/20.
//  Copyright © 2020 IBM Corporation. All rights reserved.
//

import Accelerate
import AVFoundation

class PlayingAudioRecorder: AudioRecorder {
    internal var onMicrophoneData: ((Data) -> Void)?
    internal var onPowerData: ((Float32) -> Void)?
    internal let session = AVAudioSession.sharedInstance()
    internal var isRecording: Bool = false
    internal var format: AudioStreamBasicDescription

    private let audioFile: AVAudioFile?
    private let audioEngine = AVAudioEngine()
    private let audioFilePlayer = AVAudioPlayerNode()
    // swiftlint:disable force_unwrapping
    private let requestFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let range = 0.1

    deinit {
        try? stopRecording()
    }

    init(url: URL) {
        audioFile = try? AVAudioFile(forReading: url)
        format = requestFormat.streamDescription.pointee
        try? activate()
        try? deactivate()
    }

    func startRecording() throws {
        guard let audioFile = self.audioFile else { return }
        if isRecording { return }
        isRecording = true

        try activate()

        let inputFormat = audioFile.processingFormat
        let outputFormat = AVAudioFormat(commonFormat: inputFormat.commonFormat,
                                         sampleRate: inputFormat.sampleRate,
                                         channels: 1,
                                         interleaved: true)!

        audioEngine.attach(audioFilePlayer)
        audioEngine.connect(audioFilePlayer, to:audioEngine.mainMixerNode, format: outputFormat)

        let bufferSize = AVAudioFrameCount(outputFormat.sampleRate * range)
        audioEngine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: outputFormat) { [weak self] (buffer, time) in
            var level: Float = 0.0
            vDSP_rmsqv(buffer.floatChannelData![0], 1, &level, vDSP_Length(buffer.frameLength))
            let db: Float32 = level > 0 ? 20 * log10(level) : -100

            DispatchQueue.main.async {
                self?.onPowerData?(db)
            }

            // convert
            guard let sself = self else { return }
            let frameCapacity = AVAudioFrameCount(sself.requestFormat.sampleRate * sself.range)
            let targetBuffer = AVAudioPCMBuffer(pcmFormat: sself.requestFormat, frameCapacity: frameCapacity)!
            try? sself.convert(to: targetBuffer, from: buffer)

            guard let channelDataPointee = targetBuffer.int16ChannelData?.pointee else { return }
            let bufferPointer = UnsafeBufferPointer<Int16>(start: channelDataPointee, count: Int(targetBuffer.frameLength))
            let data = Data(buffer: bufferPointer)
            self?.onMicrophoneData?(data)
        }

        do {
            try audioEngine.start()
        } catch {
            try stopRecording()
            throw error
        }

        audioFilePlayer.play()
        audioFilePlayer.scheduleFile(audioFile, at: nil)
    }

    func stopRecording() throws {
        if !isRecording { return }
        isRecording = false

        audioEngine.stop()
        audioEngine.mainMixerNode.removeTap(onBus: 0)
        audioEngine.reset()

        audioFilePlayer.pause()
        audioFilePlayer.reset()

        try? deactivate()
    }

    private func activate() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try audioSession.setActive(true)
    }

    private func deactivate() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convert(to dst: AVAudioPCMBuffer, from src: AVAudioPCMBuffer) throws {
        let converter = AVAudioConverter(from: src.format, to: requestFormat)
        var error: NSError?
        converter?.convert(to: dst, error: &error, withInputFrom: { (inNumberOfPackets, outStatus) -> AVAudioBuffer? in
            outStatus.pointee = .haveData
            return src
        })
        if let error = error {
            throw error
        }
    }
}
