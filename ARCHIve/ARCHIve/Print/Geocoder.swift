import CoreLocation

/// Reverse-geocodes GPS → city name, best-effort. Cached by a ~1 km bucket so
/// repeat lookups are free, and callers should await sequentially (CLGeocoder
/// serialises requests). No location permission needed — this is coordinate →
/// name only, not the user's location.
enum Geocoder {
    private static let cl = CLGeocoder()
    private static var cache: [String: String] = [:]

    private static func key(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.2f,%.2f", lat, lon)
    }

    static func city(latitude: Double, longitude: Double) async -> String? {
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
