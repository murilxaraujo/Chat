import AVKit
import Foundation
import Observation

// TODO: Create option "download video before playing"
@MainActor
@Observable
final class VideoViewModel {
    var attachment: Attachment
    var player: AVPlayer?
    var isPlaying = false
    var isMuted = false
    var status: AVPlayer.Status = .unknown

    @ObservationIgnored private var currentItem: AVPlayerItem?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackEndTask: Task<Void, Never>?

    init(attachment: Attachment) {
        self.attachment = attachment
    }

    deinit {
        playbackEndTask?.cancel()
        statusObservation?.invalidate()
    }

    func onStart() {
        if player == nil {
            let item = AVPlayerItem(url: attachment.full)
            currentItem = item
            player = AVPlayer(playerItem: item)
        }
        guard let player else { return }
        if playbackEndTask == nil, let currentItem {
            observePlaybackEnd(of: currentItem)
        }
        status = player.status
        statusObservation?.invalidate()
        statusObservation = player.observe(\.status, options: [.initial, .new]) { [weak self] player, _ in
            let status = player.status
            Task { @MainActor [weak self] in
                self?.status = status
            }
        }
    }

    func onStop() {
        pauseVideo()
        statusObservation?.invalidate()
        statusObservation = nil
        playbackEndTask?.cancel()
        playbackEndTask = nil
    }

    func togglePlay() {
        if player?.isPlaying == true {
            pauseVideo()
        } else {
            playVideo()
        }
    }

    func toggleMute() {
        player?.isMuted.toggle()
        isMuted = player?.isMuted ?? false
    }

    func playVideo() {
        player?.play()
        isPlaying = player?.isPlaying ?? false
    }

    func pauseVideo() {
        player?.pause()
        isPlaying = player?.isPlaying ?? false
    }

    private func observePlaybackEnd(of item: AVPlayerItem) {
        playbackEndTask = Task { @MainActor [weak self, item] in
            let notifications = NotificationCenter.default
                .notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
                .map { _ in () }
            for await _ in notifications {
                guard !Task.isCancelled, let self else { return }
                await self.finishVideo()
            }
        }
    }

    private func finishVideo() async {
        guard let player else { return }
        _ = await player.seek(to: .zero)
        guard !Task.isCancelled else { return }
        isPlaying = false
    }
}
