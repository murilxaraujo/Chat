import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LiveLocationBroadcaster {
    struct ActiveShare {
        let messageId: String
        let startedAt: Date
        let expiresAt: Date
    }

    private(set) var activeShare: ActiveShare?

    @ObservationIgnored var onEvent: ((LiveLocationBroadcastEvent) -> Void)?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    deinit {
        locationTask?.cancel()
        expiryTask?.cancel()
    }

    /// Only one share can broadcast at a time - starting a new share ends whichever was already active
    /// (its `.ended` event fires before this new share's first `.updated`).
    func start(messageId: String, startedAt: Date, expiresAt: Date) {
        finish()

        guard expiresAt > Date() else { return }
        let share = ActiveShare(messageId: messageId, startedAt: startedAt, expiresAt: expiresAt)
        activeShare = share

        locationTask = Task { @MainActor [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    try Task.checkCancellation()
                    guard let self else { return }

                    if update.authorizationDenied
                        || update.authorizationDeniedGlobally
                        || update.authorizationRestricted {
                        self.finish()
                        return
                    }

                    guard let location = update.location else { continue }
                    self.publish(location.coordinate, for: share)
                }
                self?.finish()
            } catch is CancellationError {
                // Normal when the user ends the share or its lifetime expires.
            } catch {
                self?.finish()
            }
        }

        let remainingLifetime = max(0, expiresAt.timeIntervalSinceNow)
        expiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(remainingLifetime))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func finish() {
        guard let share = activeShare else { return }
        locationTask?.cancel()
        locationTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        activeShare = nil
        onEvent?(.ended(messageId: share.messageId))
    }

    private func publish(_ coordinate: CLLocationCoordinate2D, for share: ActiveShare) {
        guard activeShare?.messageId == share.messageId else { return }
        let liveLocation = LiveLocation(
            coordinate: coordinate,
            lastUpdateAt: Date(),
            startedAt: share.startedAt,
            expiresAt: share.expiresAt
        )
        onEvent?(.updated(messageId: share.messageId, liveLocation: liveLocation))
    }
}
