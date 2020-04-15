//
//  AudioRecorder.swift
//  SpeechToTextV1
//
//  Created by Seiya Shimokawa on 4/15/20.
//  Copyright © 2020 IBM Corporation. All rights reserved.
//

import AVFoundation

protocol AudioRecorder {
    var onMicrophoneData: ((Data) -> Void)? { get set }
    var onPowerData: ((Float32) -> Void)? { get set }
    var session: AVAudioSession { get }
    var isRecording: Bool { get }
    var format: AudioStreamBasicDescription { get }

    func startRecording() throws
    func stopRecording() throws
}
