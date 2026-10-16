import Foundation

/// Reads a location from text shared by a map app: an Apple Maps or Amap
/// link (including their short links), a `wrappin://` link, or plain
/// "latitude,longitude" text.
///
/// Coordinates are kept exactly as the map app provides them, which is the
/// same coordinate space as points picked on WrapPin's own map (GCJ-02 in
/// mainland China, WGS84 elsewhere). The usual fixed-coordinate mode then
/// applies, so a shared point lands where the same point picked in WrapPin
/// would.
enum MapLinkParser {
    enum ParseError: LocalizedError {
        case noLocation
        case shortLinkUnavailable

        var errorDescription: String? {
            switch self {
            case .noLocation:
                String(localized: "The link does not contain a location.")
            case .shortLinkUnavailable:
                String(localized: "The short map link could not be opened. Check the network and try again.")
            }
        }
    }

    static func target(from text: String) async throws -> LocationTarget {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = firstURL(in: trimmed) else {
            if let target = targetFromCoordinateText(trimmed, name: nil) {
                return target
            }
            throw ParseError.noLocation
        }

        if let target = target(fromURL: url, sharedText: trimmed) {
            return target
        }

        // Short links (maps.apple/p/…, surl.amap.com/…) only carry the
        // location after the redirect, or inside the page they lead to.
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 27_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ParseError.shortLinkUnavailable
        }

        if let finalURL = response.url, finalURL != url,
           let target = target(fromURL: finalURL, sharedText: trimmed) {
            return target
        }

        let page = String(decoding: data.prefix(400_000), as: UTF8.self)
        if let target = targetFromPage(page, sharedText: trimmed) {
            return target
        }
        throw ParseError.noLocation
    }

    static func target(latitudeText: String, longitudeText: String, name: String?) -> LocationTarget? {
        guard
            let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
            let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return makeTarget(latitude: latitude, longitude: longitude, name: name, detail: nil)
    }

    // MARK: - URL parsing

    private static func firstURL(in text: String) -> URL? {
        if let direct = URL(string: text), direct.scheme != nil, direct.host != nil || direct.scheme == "wrappin" {
            return direct
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.url
    }

    private static func target(fromURL url: URL, sharedText: String) -> LocationTarget? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            values[item.name.lowercased()] = value
        }
        let host = url.host?.lowercased() ?? ""
        let name = values["name"] ?? values["title"] ?? nameFromSharedText(sharedText, url: url)
        let detail = values["address"] ?? values["addr"]

        // Apple Maps: coordinate=lat,lon (current), ll=lat,lon (older),
        // also daddr/sll/q when they hold a coordinate pair.
        for key in ["coordinate", "ll", "daddr", "sll", "center", "q", "query"] {
            if let pair = values[key], let target = targetFromPair(
                pair, latitudeFirst: true, name: name ?? textName(values["q"]), detail: detail
            ) {
                return target
            }
        }

        // Generic lat/lon parameters (amapuri://, wrappin:// and others).
        if
            let latitude = values["lat"] ?? values["latitude"] ?? values["dlat"],
            let longitude = values["lon"] ?? values["lng"] ?? values["longitude"] ?? values["dlon"],
            let target = target(latitudeText: latitude, longitudeText: longitude, name: name ?? values["poiname"] ?? values["dname"])
        {
            return target
        }

        if host.contains("amap.com") || host.contains("autonavi.com") {
            // uri.amap.com/marker?position=lon,lat
            if let position = values["position"] ?? values["to"] ?? values["destination"],
               let target = targetFromPair(position, latitudeFirst: false, name: name, detail: detail) {
                return target
            }
            // Share pages: p=POIID,lat,lon,name,address and q=lat,lon,name
            for key in ["p", "q"] {
                guard let raw = values[key] else { continue }
                let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                if let target = targetFromParts(parts) { return target }
            }
        }
        return nil
    }

    private static func targetFromPage(_ page: String, sharedText: String) -> LocationTarget? {
        // Coordinates embedded in the redirect page or its metadata.
        let patterns: [(String, Bool)] = [
            (#"coordinate=(-?\d{1,2}\.\d+)(?:,|%2C)(-?\d{1,3}\.\d+)"#, true),
            (#"[?&]ll=(-?\d{1,2}\.\d+)(?:,|%2C)(-?\d{1,3}\.\d+)"#, true),
            (#""latitude"\s*:\s*(-?\d{1,2}\.\d+)\s*,\s*"longitude"\s*:\s*(-?\d{1,3}\.\d+)"#, true),
            (#"place:location:latitude"\s+content="(-?\d{1,2}\.\d+)"[^>]*>\s*<meta[^>]+place:location:longitude"\s+content="(-?\d{1,3}\.\d+)"#, true),
            (#"position=(-?\d{1,3}\.\d+)(?:,|%2C)(-?\d{1,2}\.\d+)"#, false),
        ]
        for (pattern, latitudeFirst) in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
                let first = Range(match.range(at: 1), in: page),
                let second = Range(match.range(at: 2), in: page),
                let a = Double(page[first]),
                let b = Double(page[second])
            else { continue }
            let (latitude, longitude) = latitudeFirst ? (a, b) : (b, a)
            if let target = makeTarget(
                latitude: latitude,
                longitude: longitude,
                name: nameFromSharedText(sharedText, url: nil),
                detail: nil
            ) {
                return target
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func targetFromCoordinateText(_ text: String, name: String?) -> LocationTarget? {
        // "22.63,110.15", "人民广场 31.2304,121.4737" or "人民广场,31.2304,121.4737"
        let separators = CharacterSet(charactersIn: ", ，;；\t")
        let tokens = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let numbers = tokens.compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        let words = tokens.filter { Double($0) == nil }.joined(separator: " ")
        return makeTarget(
            latitude: numbers[0],
            longitude: numbers[1],
            name: name ?? (words.isEmpty ? nil : words),
            detail: nil
        )
    }

    private static func targetFromPair(
        _ pair: String,
        latitudeFirst: Bool,
        name: String?,
        detail: String?
    ) -> LocationTarget? {
        let parts = pair.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0) }
        guard parts.count >= 2 else { return nil }
        let (latitude, longitude) = latitudeFirst ? (parts[0], parts[1]) : (parts[1], parts[0])
        return makeTarget(latitude: latitude, longitude: longitude, name: name, detail: detail)
    }

    /// Finds the first neighbouring "lat,lon" numbers in an Amap share field
    /// and uses the following text fields as the name and address.
    private static func targetFromParts(_ parts: [String]) -> LocationTarget? {
        guard parts.count >= 2 else { return nil }
        for index in 0..<(parts.count - 1) {
            guard
                let latitude = Double(parts[index]),
                let longitude = Double(parts[index + 1]),
                abs(latitude) <= 90, abs(longitude) <= 180, abs(longitude) > 0
            else { continue }
            let name = parts.indices.contains(index + 2) ? parts[index + 2] : nil
            let detail = parts.indices.contains(index + 3) ? parts[index + 3] : nil
            return makeTarget(latitude: latitude, longitude: longitude, name: name, detail: detail)
        }
        return nil
    }

    private static func textName(_ value: String?) -> String? {
        guard let value, Double(value.split(separator: ",").first ?? "") == nil else { return nil }
        return value
    }

    /// Map apps usually share "Place name\nhttps://…"; keep the text part.
    private static func nameFromSharedText(_ text: String, url: URL?) -> String? {
        var remainder = text
        if let url { remainder = remainder.replacingOccurrences(of: url.absoluteString, with: " ") }
        if let range = remainder.range(of: #"https?://\S+"#, options: .regularExpression) {
            remainder.removeSubrange(range)
        }
        let line = remainder
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line, line.count <= 80 else { return nil }
        return line
    }

    private static func makeTarget(
        latitude: Double,
        longitude: Double,
        name: String?,
        detail: String?
    ) -> LocationTarget? {
        guard
            latitude.isFinite, longitude.isFinite,
            (-90...90).contains(latitude), (-180...180).contains(longitude),
            !(latitude == 0 && longitude == 0)
        else { return nil }

        let cleanName = name?
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetail = detail?
            .removingPercentEncoding?
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return LocationTarget(
            name: (cleanName?.isEmpty == false ? cleanName : nil)
                ?? String(localized: "Shared Location"),
            subtitle: (cleanDetail?.isEmpty == false ? cleanDetail : nil)
                ?? String(format: "%.5f, %.5f", latitude, longitude),
            latitude: latitude,
            longitude: longitude
        )
    }
}
