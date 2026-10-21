// "Dónde va el sensor" drawing. The barbell follows the mockup exactly; the
// other placements reuse their icon at a large size until each gets its own
// illustration.

import SwiftUI

struct SensorDiagram: View {
    let exercise: Exercise
    @Environment(\.colors) private var c

    var body: some View {
        if exercise.firmwareProfile == kStackProfile {
            Canvas { ctx, size in drawStack(ctx, size) }
                .aspectRatio(364 / 200, contentMode: .fit)
                .accessibilityElement()
                .accessibilityLabel("Pila de pesas con el pasador. El sensor va encima, pegado a la placa "
                    + "superior. Si no se puede, también sirve en el costado de la placa.")
        } else if exercise.placement == .equipment && exercise.equipment == .barbell {
            Canvas { ctx, size in drawBarbell(ctx, size) }
                .aspectRatio(364 / 200, contentMode: .fit)
                .accessibilityElement()
                .accessibilityLabel("Barra con discos. El sensor va sobre la barra, en el centro.")
        } else {
            VStack(spacing: 12) {
                AppLabel("Sensor", color: c.mark, size: 13)
                AppIcon(exercise.placement.icon, size: 120, strokeWidth: 1.2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .accessibilityElement()
            .accessibilityLabel(exercise.placementNote)
        }
    }

    /// Guide rods, the plates with the selector pin, the cable going up to the
    /// pulley, and the sensor on the top plate.
    private func drawStack(_ context: GraphicsContext, _ size: CGSize) {
        var ctx = context
        ctx.scaleBy(x: size.width / 364, y: size.height / 200)
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        // Guide rods.
        var rods = Path()
        for x in [124.0, 240.0] {
            rods.move(to: CGPoint(x: x, y: 26))
            rods.addLine(to: CGPoint(x: x, y: 196))
        }
        ctx.stroke(rods, with: .color(c.ink), lineWidth: 1.5)

        // Cable from the top plate to the pulley.
        var cable = Path()
        cable.move(to: CGPoint(x: 182, y: 84))
        cable.addLine(to: CGPoint(x: 182, y: 30))
        ctx.stroke(cable, with: .color(c.ink), lineWidth: 2)
        let pulley = Path(ellipseIn: CGRect(x: 170, y: 6, width: 24, height: 24))
        ctx.fill(pulley, with: .color(c.bg))
        ctx.stroke(pulley, with: .color(c.ink), style: stroke)

        func plate(_ y: CGFloat, _ h: CGFloat) {
            let rect = Path(roundedRect: CGRect(x: 108, y: y, width: 148, height: h), cornerRadius: 2)
            ctx.fill(rect, with: .color(c.bg))
            ctx.stroke(rect, with: .color(c.ink), style: stroke)
        }
        plate(84, 16)                                   // top plate
        for i in 0..<5 { plate(108 + CGFloat(i) * 17, 13) }

        // Selector pin through the third plate.
        var pin = Path()
        pin.move(to: CGPoint(x: 256, y: 148))
        pin.addLine(to: CGPoint(x: 282, y: 148))
        ctx.stroke(pin, with: .color(c.ink), style: stroke)
        ctx.fill(Path(ellipseIn: CGRect(x: 280, y: 143, width: 10, height: 10)), with: .color(c.ink))

        // The sensor, on top of the top plate, between the cable and a rod.
        var pointer = Path()
        pointer.move(to: CGPoint(x: 211, y: 48))
        pointer.addLine(to: CGPoint(x: 211, y: 64))
        ctx.stroke(pointer, with: .color(c.mark), lineWidth: 1.5)
        let sensor = Path(roundedRect: CGRect(x: 196, y: 66, width: 30, height: 18), cornerRadius: 4)
        ctx.fill(sensor, with: .color(c.dot))
        if let ring = c.dotRing {
            ctx.stroke(sensor, with: .color(ring), lineWidth: 2)
        }

        let label = Text("SENSOR").font(.text(13, .semibold)).tracking(1.3).foregroundColor(c.mark)
        ctx.draw(label, at: CGPoint(x: 211, y: 30), anchor: .top)

        // The alternative: on the side of the top plate, drawn as a dashed
        // outline so it reads as "or here", not as a second sensor.
        let side = Path(roundedRect: CGRect(x: 92, y: 80, width: 14, height: 24), cornerRadius: 3)
        ctx.fill(side, with: .color(c.dot.opacity(0.45)))
        ctx.stroke(side, with: .color(c.mark), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
        var sidePointer = Path()
        sidePointer.move(to: CGPoint(x: 72, y: 92))
        sidePointer.addLine(to: CGPoint(x: 88, y: 92))
        ctx.stroke(sidePointer, with: .color(c.mark), lineWidth: 1.5)
        let or = Text("O AQUÍ").font(.text(11, .semibold)).tracking(1.1).foregroundColor(c.mark)
        ctx.draw(or, at: CGPoint(x: 68, y: 92), anchor: .trailing)
    }

    private func drawBarbell(_ context: GraphicsContext, _ size: CGSize) {
        var ctx = context
        ctx.scaleBy(x: size.width / 364, y: size.height / 200)
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        var bar = Path()
        bar.move(to: CGPoint(x: 8, y: 110))
        bar.addLine(to: CGPoint(x: 356, y: 110))
        ctx.stroke(bar, with: .color(c.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        func plate(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
            let rect = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
            ctx.fill(rect, with: .color(c.bg))
            ctx.stroke(rect, with: .color(c.ink), style: stroke)
        }

        plate(44, 50, 14, 120, 3)
        plate(62, 66, 10, 88, 3)
        plate(76, 100, 8, 20, 2)
        plate(306, 50, 14, 120, 3)
        plate(292, 66, 10, 88, 3)
        plate(280, 100, 8, 20, 2)

        var pointer = Path()
        pointer.move(to: CGPoint(x: 182, y: 62))
        pointer.addLine(to: CGPoint(x: 182, y: 92))
        ctx.stroke(pointer, with: .color(c.mark), lineWidth: 1.5)

        let sensor = Path(roundedRect: CGRect(x: 166, y: 96, width: 32, height: 28), cornerRadius: 5)
        ctx.fill(sensor, with: .color(c.dot))
        if let ring = c.dotRing {
            ctx.stroke(sensor, with: .color(ring), lineWidth: 2)
        }

        let label = Text("SENSOR").font(.text(13, .semibold)).tracking(1.3).foregroundColor(c.mark)
        ctx.draw(label, at: CGPoint(x: 182, y: 36), anchor: .top)
    }
}
