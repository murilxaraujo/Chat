import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager {
    private(set) var currentLocation: CLLocationCoordinate2D?

    /// Requests one location update. Core Location requests authorization when the
    /// async sequence is first iterated, keeping the prompt tied to user intent.
    func requestStaticLocation() async -> CLLocationCoordinate2D? {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                try Task.checkCancellation()

                if update.authorizationDenied
                    || update.authorizationDeniedGlobally
                    || update.authorizationRestricted {
                    return nil
                }

                guard let location = update.location else { continue }
                let coordinate = location.coordinate
                currentLocation = coordinate
                return coordinate
            }
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }

        return nil
    }
}
