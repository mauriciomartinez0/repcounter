// The movement of a set, from the state packets the board sends about 20
// times a second while it counts.
//
// On the weight stack the packet carries the stack's vertical speed (cm/s,
// positive up). Integrating it gives the height, which goes up and down once
// per rep like a sine wave. The integral drifts a little, so the line is
// tilted back to make the set end where it started (the stack rests on the
// same plate before and after), then shifted so the lowest point is 0 cm.
//
// Everywhere else the packet carries the angle of the limb or bar, which is
// already the shape of the movement.

import Foundation

struct TraceRecorder {
    static let sampleHz = 10
    /// Ten minutes; the API takes up to 6000 values.
    private static let maxSeconds = 600.0

    private var start: Date?
    private var times: [Double] = []
    private var values: [Double] = []

    mutating func reset() {
        start = nil
        times.removeAll()
        values.removeAll()
    }

    /// One packet. Listeners also fire for things other than packets, so
    /// readings closer together than a packet are dropped.
    mutating func add(_ value: Double, at date: Date = Date()) {
        guard let start else {
            self.start = date
            times = [0]
            values = [value]
            return
        }
        let t = date.timeIntervalSince(start)
        guard t - (times.last ?? 0) >= 0.03, t <= Self.maxSeconds else { return }
        times.append(t)
        values.append(value)
    }

    func trace(onStack: Bool) -> SetTrace? {
        guard times.count >= 4, let duration = times.last, duration >= 1 else { return nil }
        var series = values
        if onStack {
            // Speed (cm/s) to height (cm), trapezoids between packets.
            var height = [0.0]
            for i in 1..<times.count {
                let dt = times[i] - times[i - 1]
                height.append(height[i - 1] + (values[i] + values[i - 1]) / 2 * dt)
            }
            let drift = height.last!
            series = zip(times, height).map { t, h in h - drift * t / duration }
            let lowest = series.min()!
            series = series.map { $0 - lowest }
        }

        // Evenly spaced samples, by linear interpolation between packets.
        let step = 1 / Double(Self.sampleHz)
        var out: [Double] = []
        var j = 0
        var t = 0.0
        while t <= duration + 1e-9 {
            while j + 1 < times.count - 1 && times[j + 1] < t { j += 1 }
            let t0 = times[j], t1 = times[j + 1]
            let f = t1 > t0 ? min(1, max(0, (t - t0) / (t1 - t0))) : 0
            let v = series[j] + (series[j + 1] - series[j]) * f
            out.append((min(1000, max(-1000, v)) * 10).rounded() / 10)
            t += step
        }
        return SetTrace(kind: onStack ? .height : .angle, sampleHz: Self.sampleHz, values: out)
    }
}
