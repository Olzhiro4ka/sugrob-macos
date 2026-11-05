import Foundation

/// Global gentle wind: a constant drift plus two slow, incommensurate sine gusts.
public enum Wind {
    /// Horizontal wind velocity (pt/s) at simulation time `time` (s).
    public static func velocity(at time: Float) -> Float {
        let twoPi = 2 * Float.pi
        let a = sin(twoPi * time / Config.windPeriods.0)
        let b = sin(twoPi * time / Config.windPeriods.1 + 1.3)
        return Config.windBase + Config.windGust * a * (0.6 + 0.4 * b)
    }
}
