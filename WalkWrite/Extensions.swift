import Foundation

extension TimeInterval {
    /// Human-readable mm:ss string (e.g. 3:07). Good enough for <1h clips.
    var mmSS: String {
        guard self.isFinite && self >= 0 else { return "0:00" }
        let totalSeconds = Int(self.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
