import SwiftUI

/// Sensor connection: "Sin conectar", "Buscando sensor", "Sensor no
/// encontrado".
///
/// Opened right after signing in it continues to the home screen once
/// connected. Opened from a sensor badge or before a workout (`popOnConnect`)
/// it closes instead, and opens the workout `then` when there is one.
struct ConnectionScreen: View {
    let popOnConnect: Bool
    let then: WorkoutSpec?

    @Environment(SensorService.self) private var sensor
    @Environment(\.colors) private var c
    @State private var left = false

    private func onSensor() {
        guard !left, sensor.connected else { return }
        left = true
        tick()
        continueFlow(connected: true)
    }

    private func continueFlow(connected: Bool) {
        let router = Router.shared
        if popOnConnect {
            if connected, let then {
                router.replaceTop(with: .workout(then))
            } else {
                router.pop()
            }
        } else {
            router.reset(to: .home)
        }
    }

    var body: some View {
        let status = sensor.status
        let searching = sensor.busy || status == .ready
        let failed = status == .failed
        let (title, message) = texts(searching: searching, failed: failed)

        VStack(spacing: 0) {
            AppLabel("Sensor")
                .frame(height: 48)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if searching {
                        TimelineView(.animation) { timeline in
                            let t = timeline.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1.8) / 1.8
                            Rings(color: c.mark, t: t)
                        }
                    } else {
                        SensorCircle(color: failed ? c.ink : c.control, crossed: failed)
                    }
                }
                .frame(width: 216, height: 216)
                Spacer().frame(height: 40)
                Text(title)
                    .font(.text(40))
                    .foregroundStyle(c.ink)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 12)
                Text(message)
                    .font(.text(18))
                    .foregroundStyle(c.ink2)
                    .multilineTextAlignment(.center)
                if failed && !sensor.detail.isEmpty && sensor.failure == .error {
                    Spacer().frame(height: 12)
                    Text(sensor.detail)
                        .font(.text(13))
                        .foregroundStyle(c.ink3)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            if searching {
                SecondaryButton("Cancelar", height: 88, fontSize: 24) { sensor.cancel() }
            } else {
                PrimaryButton(failed ? "Reintentar" : "Conectar", height: 88, fontSize: 24) { sensor.connect() }
            }
            Spacer().frame(height: 8)
            // Not in the mockups: lets someone check their history or edit
            // routines without the sensor at hand.
            TextAction(label: popOnConnect ? "Volver" : "Seguir sin sensor") {
                left = true
                continueFlow(connected: false)
            }
        }
        .padding(EdgeInsets(top: 0, leading: kGutter, bottom: 32, trailing: kGutter))
        .onAppear { onSensor() }
        .onChange(of: sensor.connected) { _, _ in onSensor() }
    }

    private func texts(searching: Bool, failed: Bool) -> (String, String) {
        if searching {
            return ("Buscando sensor", "Mantenlo encendido y cerca del teléfono.")
        }
        if failed {
            switch sensor.failure {
            case .lost:
                return ("Se perdió la conexión", "Acerca el sensor al teléfono y vuelve a conectarlo.")
            case .unsupported:
                return ("Bluetooth no disponible", sensor.detail)
            case .error:
                return ("No se pudo conectar",
                        "Revisa que esté encendido y que el Bluetooth del teléfono esté activo.")
            default:
                return ("Sensor no encontrado",
                        "Revisa que esté encendido y que el Bluetooth del teléfono esté activo.")
            }
        }
        return ("Sin conectar", "Enciende el sensor y acércalo al teléfono.")
    }
}

private struct SensorCircle: View {
    let color: Color
    let crossed: Bool

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = 59
            var path = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            if crossed {
                let d = r * cos(.pi / 4)
                path.move(to: CGPoint(x: center.x + d, y: center.y - d))
                path.addLine(to: CGPoint(x: center.x - d, y: center.y + d))
            }
            ctx.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
}

/// Three rings; the outer two breathe while searching.
private struct Rings: View {
    let color: Color
    let t: Double

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func ring(_ r: CGFloat, _ opacity: Double) {
                let path = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                ctx.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 2)
            }
            let wave = (sin(t * 2 * .pi) + 1) / 2
            ring(107, 0.12 + 0.16 * wave)
            ring(83, 0.3 + 0.3 * (1 - wave))
            ring(59, 1)
        }
    }
}
