import CoreMotion
import Observation
import QuartzCore

/// Feeds a smoothed device-roll angle for the camera level, using CoreMotion
/// gravity (no permission prompt, no user gesture — unlike the web
/// DeviceMotion API). Angle math matches the old web app: `atan2(gx, -gy)`,
/// where 0° = upright & level.
@MainActor
@Observable
final class MotionLevel {
    /// Smoothed roll angle in degrees. 0 = level, ±90 = on its side.
    var angle: Double = 0
    /// True when within ~1° of a cardinal (0/90/180/270) — the green state.
    var isLevel: Bool = false
    /// True when the phone is lying flat (gravity mostly on Z) — level hidden.
    var isFlat: Bool = false
    /// Rotation (degrees) to apply to control icons so they stay upright as the
    /// phone turns — snapped to 0 / ±90 / 180, like the native Camera. Updates
    /// only once the phone settles near a cardinal, and always the short way.
    var iconAngle: Double = 0

    /// Forward/back tilt in degrees (0 = phone vertical, sensor plane parallel
    /// to a façade). Negative = tilted up; positive = tilted down. Drives the
    /// architectural keystone correction.
    var pitch: Double = 0
    private var smoothedPitch: Double = 0

    private let manager = CMMotionManager()
    private var smoothed: Double = 0
    // Smoothing factor per update. Lower = smoother. Tuned for 60 Hz (~185 ms
    // time constant) so the level glides like the native camera's.
    private let ema = 0.10

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            self.update(gx: g.x, gy: g.y, gz: g.z)
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    private func update(gx: Double, gy: Double, gz: Double) {
        // Flat-on-table dead zone: most of gravity is on Z.
        let planar = (gx * gx + gy * gy).squareRoot()
        let total = (gx * gx + gy * gy + gz * gz).squareRoot()
        isFlat = total > 0 && planar / total < 0.17

        // atan2(gx, -gy): 0° upright, rotates with the phone's roll.
        let raw = atan2(gx, -gy) * 180 / .pi   // degrees, -180...180

        // EMA smoothing with wrap handling.
        var delta = raw - smoothed
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        smoothed += delta * ema
        if smoothed > 180 { smoothed -= 360 }
        if smoothed < -180 { smoothed += 360 }

        angle = smoothed

        // Forward/back tilt: 0 when the phone is vertical, ± when tilted up/down.
        let rawPitch = atan2(gz, -gy) * 180 / .pi
        smoothedPitch += (rawPitch - smoothedPitch) * ema
        pitch = smoothedPitch

        // Nearest cardinal (0/90/180/-90).
        let bucket = (smoothed / 90).rounded() * 90
        isLevel = !isFlat && abs(smoothed - bucket) < 1.0

        // Icon orientation: only commit a new cardinal once the phone has
        // settled within 35° of it (hysteresis → no flicker at the 45° edges),
        // and rotate the short way so it never spins the long way round.
        if !isFlat, abs(wrap(smoothed - bucket)) < 35 {
            var target = -bucket
            while target - iconAngle > 180 { target -= 360 }
            while target - iconAngle < -180 { target += 360 }
            iconAngle = target
        }
    }

    /// Normalise an angle to -180...180.
    private func wrap(_ d: Double) -> Double {
        var x = d
        while x > 180 { x -= 360 }
        while x < -180 { x += 360 }
        return x
    }
}
