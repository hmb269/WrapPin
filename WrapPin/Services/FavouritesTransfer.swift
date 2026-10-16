import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct FavouriteImportResult: Equatable, Sendable {
    var added = 0
    var skipped = 0
    var failed = 0

    var summary: String {
        var parts = [String(localized: "Added \(added) places.")]
        if skipped > 0 {
            parts.append(String(localized: "Skipped \(skipped) already saved."))
        }
        if failed > 0 {
            parts.append(String(localized: "\(failed) lines could not be recognised."))
        }
        return parts.joined(separator: " ")
    }
}

enum FavouriteMerge {
    /// Appends new places after the existing favourites, skipping any place
    /// already saved at the same coordinates.
    static func merge(
        _ incoming: [LocationTarget],
        into existing: [LocationTarget]
    ) -> (favourites: [LocationTarget], result: FavouriteImportResult) {
        var merged = existing
        var seen = Set(existing.map(\.id))
        var result = FavouriteImportResult()
        for target in incoming {
            if seen.insert(target.id).inserted {
                merged.append(target)
                result.added += 1
            } else {
                result.skipped += 1
            }
        }
        return (merged, result)
    }
}

/// A shareable file containing the current favourites.
struct FavouritesExport: Transferable {
    let locations: [LocationTarget]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            SentTransferredFile(try FavouritesFile.write(export.locations))
        }
    }
}

enum FavouritesFile {
    private struct Payload: Codable {
        var app: String
        var version: Int
        var exportedAt: Date
        var favourites: [LocationTarget]
    }

    static func write(_ locations: [LocationTarget]) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            Payload(app: "WrapPin", version: 1, exportedAt: Date(), favourites: locations)
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FavouritesExport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "WrapPin-Favourites-\(formatter.string(from: Date())).json"
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a WrapPin export, a JSON array of places, or text with one map
    /// link or "latitude,longitude" per line.
    static func locations(from data: Data) async -> (locations: [LocationTarget], failed: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(Payload.self, from: data) {
            return (payload.favourites.filter(isValid), 0)
        }
        if let array = try? decoder.decode([LocationTarget].self, from: data) {
            return (array.filter(isValid), 0)
        }
        return await locations(fromText: String(decoding: data, as: UTF8.self))
    }

    static func locations(fromText text: String) async -> (locations: [LocationTarget], failed: Int) {
        var locations: [LocationTarget] = []
        var failed = 0
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let target = try? await MapLinkParser.target(from: trimmed) {
                locations.append(target)
            } else {
                failed += 1
            }
        }
        return (locations, failed)
    }

    private static func isValid(_ target: LocationTarget) -> Bool {
        target.latitude.isFinite && target.longitude.isFinite
            && (-90...90).contains(target.latitude)
            && (-180...180).contains(target.longitude)
    }
}
