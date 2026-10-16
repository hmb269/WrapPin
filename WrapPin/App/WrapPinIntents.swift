import AppIntents
import Foundation

// Shortcuts actions. Each one opens WrapPin and hands the request to the home
// screen through ExternalActionCenter, so it follows exactly the same start
// and stop paths as the on-screen buttons (pairing checks, tunnel handoff,
// recovery records and restoring the real location).

// MARK: - Saved places

struct SavedPlaceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved Place"
    static let defaultQuery = SavedPlaceQuery()

    let id: String
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    init(_ target: LocationTarget) {
        id = target.id
        name = target.name
        subtitle = target.subtitle
        latitude = target.latitude
        longitude = target.longitude
    }

    var target: LocationTarget {
        LocationTarget(name: name, subtitle: subtitle, latitude: latitude, longitude: longitude)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }
}

struct SavedPlaceQuery: EntityQuery {
    func entities(for identifiers: [SavedPlaceEntity.ID]) async throws -> [SavedPlaceEntity] {
        SavedPlaceStore.favourites()
            .filter { identifiers.contains($0.id) }
            .map(SavedPlaceEntity.init)
    }

    func suggestedEntities() async throws -> [SavedPlaceEntity] {
        SavedPlaceStore.favourites().map(SavedPlaceEntity.init)
    }
}

/// Reads the favourites AppModel stores, without needing the app's state.
enum SavedPlaceStore {
    static let favouritesKey = "favouriteLocations"

    static func favourites(in preferences: UserDefaults = .standard) -> [LocationTarget] {
        guard
            let data = preferences.data(forKey: favouritesKey),
            let locations = try? JSONDecoder().decode([LocationTarget].self, from: data)
        else { return [] }
        return locations
    }
}

// MARK: - Errors

struct WrapPinIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: message)
    }
}

// MARK: - Actions

struct StartSavedPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Simulate Saved Place"
    static let description = IntentDescription("Opens WrapPin and simulates one of your saved places.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Place")
    var place: SavedPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Simulate \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ExternalActionCenter.shared.submit(.start(place.target))
        return .result()
    }
}

struct StartMapLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Simulate Location from Map Link"
    static let description = IntentDescription("Opens WrapPin and simulates the place in an Apple Maps or Amap link. Use it with Shortcuts input to run it from the share sheet.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Map Link")
    var link: String

    static var parameterSummary: some ParameterSummary {
        Summary("Simulate the place in \(\.$link)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let target = try await MapLinkParser.target(from: link)
            ExternalActionCenter.shared.submit(.start(target))
        } catch {
            ExternalActionCenter.shared.reportError(error.localizedDescription)
            throw WrapPinIntentError(message: error.localizedDescription)
        }
        return .result()
    }
}

struct StartCoordinatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Simulate Coordinates"
    static let description = IntentDescription("Opens WrapPin and simulates a latitude and longitude. Use the same coordinates a map app shows (GCJ-02 in mainland China).")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Latitude")
    var latitude: Double

    @Parameter(title: "Longitude")
    var longitude: Double

    @Parameter(title: "Name")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Simulate \(\.$latitude), \(\.$longitude)") {
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let target = MapLinkParser.target(
            latitudeText: String(latitude),
            longitudeText: String(longitude),
            name: name
        ) else {
            throw WrapPinIntentError(message: String(localized: "The link does not contain a location."))
        }
        ExternalActionCenter.shared.submit(.start(target))
        return .result()
    }
}

struct StopSimulationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Simulation and Restore Location"
    static let description = IntentDescription("Stops the simulated location and restores this iPhone's real location.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ExternalActionCenter.shared.submit(.stop)
        return .result()
    }
}

struct ToggleSavedPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Simulation"
    static let description = IntentDescription("If a simulation is running, stops it and restores the real location. Otherwise simulates the chosen saved place.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Place")
    var place: SavedPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle simulation of \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ExternalActionCenter.shared.submit(.toggle(place.target))
        return .result()
    }
}

struct IsSimulatingIntent: AppIntent {
    static let title: LocalizedStringResource = "Is Location Simulated"
    static let description = IntentDescription("Returns true while WrapPin is simulating this iPhone's location, or when a previous simulation has not been restored yet. Use it with If in Shortcuts.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        .result(value: ExternalActionCenter.shared.currentSimulationState())
    }
}

struct AddFavouritesFromMapLinksIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Favourites from Map Links"
    static let description = IntentDescription("Adds the places in Apple Maps or Amap links to WrapPin's favourites without starting a simulation. Put one link or latitude,longitude per line.")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Map Links")
    var links: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$links) to favourites")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = await FavouritesFile.locations(fromText: links)
        guard !parsed.locations.isEmpty else {
            throw WrapPinIntentError(message: String(localized: "The link does not contain a location."))
        }
        var result = ExternalActionCenter.shared.addFavourites(parsed.locations)
        result.failed = parsed.failed
        return .result(dialog: "\(result.summary)")
    }
}

// MARK: - App Shortcuts

struct WrapPinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSavedPlaceIntent(),
            phrases: [
                "Simulate a saved place in \(.applicationName)"
            ],
            shortTitle: "Simulate Saved Place",
            systemImageName: "star.circle"
        )
        AppShortcut(
            intent: ToggleSavedPlaceIntent(),
            phrases: [
                "Toggle simulation in \(.applicationName)"
            ],
            shortTitle: "Toggle Simulation",
            systemImageName: "location.circle"
        )
        AppShortcut(
            intent: StopSimulationIntent(),
            phrases: [
                "Restore my location in \(.applicationName)"
            ],
            shortTitle: "Restore Location",
            systemImageName: "location.slash"
        )
    }
}
