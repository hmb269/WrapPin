import Foundation
import Observation

/// A location action requested from outside the map screen: a Shortcuts
/// action, a shared map link or a `wrappin://` URL.
enum ExternalLocationAction: Equatable, Sendable {
    case start(LocationTarget)
    case stop
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
