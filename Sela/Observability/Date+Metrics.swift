import Foundation

extension Date {
    /// Milliseconds between `self` and `now`, for distribution metrics.
    var msSince: Double {
        Date().timeIntervalSince(self) * 1000
    }
}
