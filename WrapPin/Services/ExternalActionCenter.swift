import Foundation
import Observation

/// A location action requested from outside the map screen: a Shortcuts
/// action, a shared map link or a `wrappin://` URL.
enum ExternalLocationAction: Equatable, Sendable {
    case start(LocationTarget)
    case stop
    /// Stops when a simulation is running (or was interrupted), otherwise
    /// starts the given place.
    case toggle(LocationTarget)
}

/// Hands external requests to the home screen, which owns the map and the
/// selection state needed to start or stop a session the same way the
/// on-screen buttons do. Requests are queued until the home screen is ready,
/// so an action that launches WrapPin is not lost during startup.
@MainActor
@Observable
final class ExternalActionCenter {
    static let shared = ExternalActionCenter()

    private(set) var pending: ExternalLocationAction?
    /// Changes on every submission so repeated identical requests are seen.
    private(set) var sequence = 0
    private(set) var lastErrorMessage: String?
    /// Live state published by AppModel while WrapPin is running.
    private(set) var isSimulating = false
    private(set) var hasLiveState = false
    /// Set by AppModel so favourites added from Shortcuts update the live list.
    @ObservationIgnored
    var favouriteImporter: (@MainActor ([LocationTarget]) -> FavouriteImportResult)?

    /// Adds favourites without opening WrapPin. If the app's model is not
    /// loaded, the stored list is updated and read on the next launch.
    func addFavourites(_ targets: [LocationTarget], preferences: UserDefaults = .standard) -> FavouriteImportResult {
        if let favouriteImporter {
            return favouriteImporter(targets)
        }
        let merged = FavouriteMerge.merge(targets, into: SavedPlaceStore.favourites(in: preferences))
        if merged.result.added > 0, let data = try? JSONEncoder().encode(merged.favourites) {
            preferences.set(data, forKey: SavedPlaceStore.favouritesKey)
        }
        return merged.result
    }

    func publishSimulationState(_ simulating: Bool) {
        hasLiveState = true
        isSimulating = simulating
    }

    /// Whether this iPhone is (or may still be) using a simulated location.
    /// Without a running AppModel, a saved recovery record means a session
    /// was active and has not been confirmed as restored.
    func currentSimulationState(preferences: UserDefaults = .standard) -> Bool {
        if hasLiveState { return isSimulating }
        return preferences.data(forKey: "activeSessionRecovery") != nil
    }

    func submit(_ action: ExternalLocationAction) {
        pending = action
        lastErrorMessage = nil
        sequence &+= 1
    }

    func takePending() -> ExternalLocationAction? {
        defer { pending = nil }
        return pending
    }

    func reportError(_ message: String) {
        lastErrorMessage = message
    }

    func clearError() {
        lastErrorMessage = nil
    }

    /// Handles `wrappin://simulate?lat=…&lon=…&name=…`,
    /// `wrappin://simulate?link=…` and `wrappin://stop`. Returns false for
    /// any other URL, such as a tunnel app's return callback.
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == BuildEdition.callbackScheme else { return false }
        let host = url.host?.lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ names: String...) -> String? {
            items.first { names.contains($0.name.lowercased()) }?.value
        }

        switch host {
        case "stop":
            submit(.stop)
            return true
        case "toggle":
            guard
                let latitudeText = value("lat", "latitude"),
                let longitudeText = value("lon", "lng", "longitude"),
                let target = MapLinkParser.target(
                    latitudeText: latitudeText,
                    longitudeText: longitudeText,
                    name: value("name")
                )
            else {
                reportError(String(localized: "The link does not contain a location."))
                return true
            }
            submit(.toggle(target))
            return true
        case "simulate":
            if
                let latitudeText = value("lat", "latitude"),
                let longitudeText = value("lon", "lng", "longitude"),
                let target = MapLinkParser.target(
                    latitudeText: latitudeText,
                    longitudeText: longitudeText,
                    name: value("name")
                )
            {
                submit(.start(target))
            } else if let link = value("link", "url", "text") {
                Task { @MainActor [weak self] in
                    do {
                        let target = try await MapLinkParser.target(from: link)
                        self?.submit(.start(target))
                    } catch {
                        self?.reportError(error.localizedDescription)
                    }
                }
            } else {
                reportError(String(localized: "The link does not contain a location."))
            }
            return true
        default:
            return false
        }
    }
}
