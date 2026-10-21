// Spanish number and date formatting, as the designs write them:
// "3.660 kg", "0,46 m/s", "Dom 4 oct", "1:24".

import Foundation

private let weekdays = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"]
private let months = ["ene", "feb", "mar", "abr", "may", "jun",
                      "jul", "ago", "sep", "oct", "nov", "dic"]

/// Thousands with a dot, decimals with a comma, no trailing ",0".
func formatNumber(_ value: Double, decimals: Int = 0) -> String {
    let negative = value < 0
    let fixed = String(format: "%.\(decimals)f", abs(value))
    let parts = fixed.split(separator: ".", omittingEmptySubsequences: false)
    let whole = Array(parts[0])
    var fraction = parts.count > 1 ? String(parts[1]) : ""
    while fraction.hasSuffix("0") { fraction.removeLast() }
    var buffer = ""
    for (i, ch) in whole.enumerated() {
        if i > 0 && (whole.count - i) % 3 == 0 { buffer.append(".") }
        buffer.append(ch)
    }
    let sign = negative && (Double(fixed) ?? 0) != 0 ? "−" : ""
    return fraction.isEmpty ? "\(sign)\(buffer)" : "\(sign)\(buffer),\(fraction)"
}

func formatNumber(_ value: Int) -> String { formatNumber(Double(value)) }

/// "+180", "−3", "+0,07".
func formatSigned(_ value: Double, decimals: Int = 0) -> String {
    let text = formatNumber(value, decimals: decimals)
    return value > 0 ? "+\(text)" : text
}

/// Weight with up to one decimal ("60", "52,5").
func formatKg(_ kg: Double) -> String { formatNumber(kg, decimals: 1) }

/// Velocity always with two decimals ("0,46").
func formatVelocity(_ v: Double) -> String {
    String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
}

/// "1:24", "12:05".
func formatClock(_ totalSeconds: Int) -> String {
    let s = abs(totalSeconds)
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

private var calendar: Calendar { Calendar.current }

/// "Dom 4 oct".
func formatDay(_ d: Date) -> String {
    let c = calendar.dateComponents([.weekday, .day, .month], from: d)
    // Calendar: Sunday = 1. The list starts on Monday.
    let weekday = ((c.weekday ?? 1) + 5) % 7
    return "\(weekdays[weekday]) \(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
}

/// "dom 27 sep".
func formatDayLower(_ d: Date) -> String { formatDay(d).lowercased() }

/// "4 oct".
func formatShortDate(_ d: Date) -> String {
    let c = calendar.dateComponents([.day, .month], from: d)
    return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
}

/// "4 × 8 · 60 kg", "3 × 12 · corporal".
func formatSetsSummary(_ sets: Int, _ reps: Int, _ kg: Double?, bodyweight: String = "corporal") -> String {
    "\(sets) × \(reps) · \(kg == nil ? bodyweight : "\(formatKg(kg!)) kg")"
}

func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

/// Whole minutes between two dates, truncated like Dart's Duration.inMinutes.
func wholeMinutes(_ seconds: TimeInterval) -> Int { Int(seconds / 60) }
