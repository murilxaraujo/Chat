//
//  Recorder.swift
//  
//
//  Created by Alisa Mylnikova on 09.03.2023.
//

import Foundation
import AVFoundation

struct RecordingProgress: Sendable {
    let duration: Double
    let waveformSamples: [CGFloat]
}

struct RecordingSession: Sendable {
    let url: URL
    let progress: AsyncStream<RecordingProgress>
}

final actor Recorder {

    #if os(iOS)
    private let audioSession = AVAudioSession()
    #endif
    private var audioRecorder: AVAudioRecorder?
    private var recordingTask: Task<Void, Never>?
    private var progressContinuation: AsyncStream<RecordingProgress>.Continuation?
    private var generation = 0

    private var soundSamples: [CGFloat] = []
    private var recorderSettings = RecorderSettings()

    deinit {
        recordingTask?.cancel()
        progressContinuation?.finish()
        audioRecorder?.stop()
    }

    var isAllowedToRecordAudio: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    var isRecording: Bool {
        audioRecorder?.isRecording ?? false
    }

    func setRecorderSettings(_ recorderSettings: RecorderSettings) {
        self.recorderSettings = recorderSettings
    }

    func startRecording() async -> RecordingSession? {
        guard !isRecording else { return nil }
        generation += 1
        let recordingGeneration = generation

        if !isAllowedToRecordAudio {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else { return nil }
        }

        guard !Task.isCancelled, generation == recordingGeneration else { return nil }
        return startRecordingInternal()
    }
    
    private func startRecordingInternal() -> RecordingSession? {
        let settings: [String : Any] = [
            AVFormatIDKey: Int(recorderSettings.audioFormatID),
            AVSampleRateKey: recorderSettings.sampleRate,
            AVNumberOfChannelsKey: recorderSettings.numberOfChannels,
            AVEncoderBitRateKey: recorderSettings.encoderBitRateKey,
            AVLinearPCMBitDepthKey: recorderSettings.linearPCMBitDepth,
            AVLinearPCMIsFloatKey: recorderSettings.linearPCMIsFloatKey,
            AVLinearPCMIsBigEndianKey: recorderSettings.linearPCMIsBigEndianKey,
            AVLinearPCMIsNonInterleaved: recorderSettings.linearPCMIsNonInterleaved,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        soundSamples = []
        guard let fileExt = fileExtension(for: recorderSettings.audioFormatID) else {
            return nil
        }
        let recordingUrl = FileManager.tempDirPath.appendingPathComponent(UUID().uuidString + fileExt)
        let (progress, continuation) = AsyncStream.makeStream(
            of: RecordingProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )

        do {
            #if os(iOS)
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat)
            try audioSession.overrideOutputAudioPort(.speaker)
            try audioSession.setActive(true)
            #endif
            audioRecorder = try AVAudioRecorder(url: recordingUrl, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            guard audioRecorder?.record() == true else {
                stopRecording()
                return nil
            }

            progressContinuation = continuation
            continuation.yield(RecordingProgress(duration: 0, waveformSamples: []))

            recordingTask?.cancel()
            recordingTask = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    await self?.publishProgress()
                }
            }

            return RecordingSession(url: recordingUrl, progress: progress)
        } catch {
            stopRecording()
            return nil
        }
    }

    private func publishProgress() {
        audioRecorder?.updateMeters()
        if let power = audioRecorder?.averagePower(forChannel: 0) {
            // power from 0 db (max) to -60 db (roughly min)
            let adjustedPower = 1 - (max(power, -60) / 60 * -1)
            soundSamples.append(CGFloat(adjustedPower))
        }
        if let time = audioRecorder?.currentTime {
            progressContinuation?.yield(
                RecordingProgress(duration: time, waveformSamples: soundSamples)
            )
        }
    }

    func stopRecording() {
        generation += 1
        audioRecorder?.stop()
        audioRecorder = nil
        recordingTask?.cancel()
        recordingTask = nil
        progressContinuation?.finish()
        progressContinuation = nil
    }

    private func fileExtension(for formatID: AudioFormatID) -> String? {
        switch formatID {
        case kAudioFormatMPEG4AAC:
            return ".aac"
        case kAudioFormatLinearPCM:
            return ".wav"
        case kAudioFormatAppleLossless:
            return ".m4a"
        case kAudioFormatFLAC:
            return ".flac"
        case kAudioFormatULaw:
            return ".wav"
        case kAudioFormatALaw:
            return ".wav"
        default:
            return nil
        }
    }
}

public struct RecorderSettings : Codable, Hashable, Sendable {
    var audioFormatID: AudioFormatID
    var sampleRate: CGFloat
    var numberOfChannels: Int
    var encoderBitRateKey: Int
    // pcm
    var linearPCMBitDepth: Int
    var linearPCMIsFloatKey: Bool
    var linearPCMIsBigEndianKey: Bool
    var linearPCMIsNonInterleaved: Bool

    public init(audioFormatID: AudioFormatID = kAudioFormatMPEG4AAC,
                sampleRate: CGFloat = 12000,
                numberOfChannels: Int = 1,
                encoderBitRateKey: Int = 0,
                linearPCMBitDepth: Int = 16,
                linearPCMIsFloatKey: Bool = false,
                linearPCMIsBigEndianKey: Bool = false,
                linearPCMIsNonInterleaved: Bool = false) {
        self.audioFormatID = audioFormatID
        self.sampleRate = sampleRate
        self.numberOfChannels = numberOfChannels
        self.encoderBitRateKey = encoderBitRateKey
        self.linearPCMBitDepth = linearPCMBitDepth
        self.linearPCMIsFloatKey = linearPCMIsFloatKey
        self.linearPCMIsBigEndianKey = linearPCMIsBigEndianKey
        self.linearPCMIsNonInterleaved = linearPCMIsNonInterleaved
    }
}
