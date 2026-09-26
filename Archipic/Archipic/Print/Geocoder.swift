import CoreLocation

/// Reverse-geocodes GPS → city name, best-effort. An **actor** so its cache is
/// safe under concurrent lookups (e.g. two board exports kicked off at once).
/// Cached by a ~1 km bucket so repeat lookups are free. No location permission
/// needed — this is coordinate → name only, not the user's location.
actor Geocoder {
    static let shared = Geocoder()

    private let cl = CLGeocoder()
    private var cache: [String: String] = [:]

    private func key(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.2f,%.2f", lat, lon)
    }

    func city(latitude: Double, longitude: Double) async -> String? {
        let k = key(latitude, longitude)
        if let cached = cache[k] { return cached.isEmpty ? nil : cached }
        let marks = try? await cl.reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude))
        let name = marks?.first?.locality
            ?? marks?.first?.subAdministrativeArea
            ?? marks?.first?.administrativeArea
        cache[k] = name ?? ""          // cache misses too, so we don't re-hit the API
        return name
    }
}
