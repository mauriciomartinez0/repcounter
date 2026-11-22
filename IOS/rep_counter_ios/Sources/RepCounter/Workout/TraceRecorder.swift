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
    /// Running integral of the speed, for the live view on the stack.
    private var heights: [Double] = []

    mutating func reset() {
        start = nil
        times.removeAll()
        values.removeAll()
        heights.removeAll()
    }

    /// One packet. Listeners also fire for things other than packets, so
    /// readings closer together than a packet are dropped.
    mutating func add(_ value: Double, at date: Date = Date()) {
        guard let start else {
            self.start = date
            times = [0]
            values = [value]
            heights = [0]
            return
        }
        let t = date.timeIntervalSince(start)
        guard t - (times.last ?? 0) >= 0.03, t <= Self.maxSeconds else { return }
        heights.append(heights.last! + (value + values.last!) / 2 * (t - times.last!))
        times.append(t)
        values.append(value)
    }

    /// The last `seconds` of the set so far, for the counter screen. On the
    /// stack the height is not straightened like in `trace`: mid-set there
    /// is no end to straighten against, and over a few seconds the drift is
    /// small. The chart scales to what is on screen anyway.
    func live(onStack: Bool, seconds: Double) -> SetTrace? {
        guard times.count >= 2, let end = times.last else { return nil }
        let from = max(0, end - seconds)
        let first = times.lastIndex { $0 <= from } ?? 0
        return Self.resample(times: Array(times[first...]),
                             series: Array((onStack ? heights : values)[first...]),
                             from: from, to: end, kind: onStack ? .height : .angle)
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

        return Self.resample(times: times, series: series, from: 0, to: duration,
                             kind: onStack ? .height : .angle)
    }

    /// Evenly spaced samples, by linear interpolation between packets.
    private static func resample(times: [Double], series: [Double], from: Double, to end: Double,
                                 kind: SetTrace.Kind) -> SetTrace {
        let step = 1 / Double(Self.sampleHz)
        var out: [Double] = []
        var j = 0
        var t = from
        while t <= end + 1e-9 {
            while j + 1 < times.count - 1 && times[j + 1] < t { j += 1 }
            let t0 = times[j], t1 = times[j + 1]
            let f = t1 > t0 ? min(1, max(0, (t - t0) / (t1 - t0))) : 0
            let v = series[j] + (series[j + 1] - series[j]) * f
            out.append((min(1000, max(-1000, v)) * 10).rounded() / 10)
            t += step
        }
        return SetTrace(kind: kind, sampleHz: Self.sampleHz, values: out)
    }
}
