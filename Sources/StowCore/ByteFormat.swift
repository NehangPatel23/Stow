import Foundation

enum ByteFormat {
    static func string(for byteCount: Int) -> String {
        let value = Double(max(0, byteCount))
        if value < 1024 {
            return "\(Int(value)) B"
        }
        let units = ["KB", "MB", "GB"]
        var amount = value / 1024
        var unitIndex = 0
        while amount >= 1024 && unitIndex < units.count - 1 {
            amount /= 1024
            unitIndex += 1
        }
        if amount >= 10 {
            return String(format: "%.0f %@", amount, units[unitIndex])
        }
        return String(format: "%.1f %@", amount, units[unitIndex])
    }
}
