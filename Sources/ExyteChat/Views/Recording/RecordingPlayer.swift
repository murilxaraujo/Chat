import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RecordingPlayer {
    private(set) var playing = false
    private(set) var currentURL: URL?
    private(set) var duration = 0.0
    private(set) var secondsLeft = 0.0
    private(set) var progress = 0.0

    let playbackEnded: AsyncStream<Void>

    #if os(iOS)
    @ObservationIgnored private let audioSession = AVAudioSession()
    #endif

    @ObservationIgnored private let playbackEndedContinuation: AsyncStream<Void>.Continuation
    @ObservationIgnored private var recording: Recording? {
        didSet { updateRecordingMetadata() }
    }
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var playbackEndTask: Task<Void, Never>?

    init() {
        let (playbackEnded, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.playbackEnded = playbackEnded
        playbackEndedContinuation = continuation

        #if os(iOS)
        try? audioSession.setCategory(.playback)
        try? audioSession.overrideOutputAudioPort(.speaker)
        #endif
    }

    deinit {
        timelineTask?.cancel()
        playbackEndTask?.cancel()
        player?.pause()
        playbackEndedContinuation.finish()
    }

    func play(_ recording: Recording) {
        if self.recording?.url != recording.url {
            setupPlayer(for: recording)
        }
        play()
    }

    func pause() {
        player?.pause()
        playing = false
        RecordingPlaybackCoordinator.deactivate(self)
    }

    func togglePlay(_ recording: Recording) {
        if self.recording?.url != recording.url {
            setupPlayer(for: recording)
        }
        playing ? pause() : play()
    }

    func seek(with recording: Recording, to progress: Double) async {
        if self.recording?.url != recording.url {
            setupPlayer(for: recording)
        }
        guard let player else { return }

        let goalTime = recording.duration * progress
        _ = await player.seek(to: CMTime(seconds: goalTime, preferredTimescale: 10))
        if !playing {
            play()
        }
    }

    func seek(to progress: Double) async {
        guard let recording, let player else { return }
        let goalTime = recording.duration * progress
        _ = await player.seek(to: CMTime(seconds: goalTime, preferredTimescale: 10))
        if !playing {
            play()
        }
    }

    func reset() {
        pause()
        stopObservingCurrentItem()
        player?.replaceCurrentItem(with: nil)
        player = nil
        recording = nil
    }

    private func play() {
        #if os(iOS)
        try? audioSession.setActive(true)
        #endif
        guard let player else { return }
        RecordingPlaybackCoordinator.activate(self)
        player.play()
        playing = true
    }

    private func setupPlayer(for recording: Recording) {
        guard let url = recording.url else { return }
        stopObservingCurrentItem()
        player?.pause()
        playing = false
        RecordingPlaybackCoordinator.deactivate(self)

        self.recording = recording
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        observePlaybackEnd(of: item, using: player)
        observeTimeline(of: item)
    }

    private func observePlaybackEnd(of item: AVPlayerItem, using player: AVPlayer) {
        playbackEndTask = Task { @MainActor [weak self, item, player] in
            let notifications = NotificationCenter.default
                .notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                .map { _ in () }

            for await _ in notifications {
                guard !Task.isCancelled, let self else { return }
                self.playing = false
                _ = await player.seek(to: .zero)
                guard !Task.isCancelled, self.player === player else { return }
                RecordingPlaybackCoordinator.deactivate(self)
                self.playbackEndedContinuation.yield(())
            }
        }
    }

    private func observeTimeline(of item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 10)
        timelineTask = Task { @MainActor [weak self, item] in
            for await time in item.integratedTimeline.periodicTimes(forInterval: interval) {
                guard !Task.isCancelled, let self else { return }
                let duration = item.duration.seconds
                guard duration.isFinite, duration > 0, time.seconds.isFinite else { continue }
                self.updateProgress(duration, time)
            }
        }
    }

    private func stopObservingCurrentItem() {
        timelineTask?.cancel()
        timelineTask = nil
        playbackEndTask?.cancel()
        playbackEndTask = nil
    }

    private func updateRecordingMetadata() {
        progress = 0
        guard let recording else {
            currentURL = nil
            duration = 0
            secondsLeft = 0
            return
        }
        currentURL = recording.url
        duration = recording.duration
        secondsLeft = recording.duration
    }

    private func updateProgress(_ duration: Double, _ time: CMTime) {
        self.duration = duration
        progress = time.seconds / duration
        secondsLeft = (duration - time.seconds).rounded()
    }
}

@MainActor
private enum RecordingPlaybackCoordinator {
    private(set) static weak var activePlayer: RecordingPlayer?

    static func activate(_ player: RecordingPlayer) {
        if let activePlayer, activePlayer !== player {
            activePlayer.pause()
        }
        activePlayer = player
    }

    static func deactivate(_ player: RecordingPlayer) {
        if activePlayer === player {
            activePlayer = nil
        }
    }
}
