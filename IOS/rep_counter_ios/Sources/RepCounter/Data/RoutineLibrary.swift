// Ready-made programs to copy into "Rutinas": well-known, generic splits
// (no one's personal program), built from the catalog. Each day becomes a
// routine of its own; weights are left empty, since they depend on the
// person, and can be set in the editor or on the first workout.

import Foundation

struct ProgramDay: Identifiable {
    let name: String
    let items: [RoutineItem]

    var id: String { name }
}

struct RoutineProgram: Identifiable {
    enum Level: String {
        case beginner = "Principiante"
        case intermediate = "Intermedio"
        case any = "Cualquier nivel"
    }

    let id: String
    let name: String
    /// Goes before the day in the routine's name: "PPL · Empuje".
    let shortName: String
    let level: Level
    let daysPerWeek: String
    let summary: String
    let days: [ProgramDay]

    /// The day as a routine to save, with only the exercises the catalog
    /// has (the server's catalog can change).
    func routine(_ day: ProgramDay, known: (String) -> Bool) -> Routine {
        let items = day.items.compactMap { item -> RoutineItem? in
            guard known(item.exerciseId) else { return nil }
            var copy = item
            copy.alternativeIds = item.alternativeIds.filter(known)
            return copy
        }
        let name = days.count == 1 ? self.name : "\(shortName) · \(day.name)"
        return Routine(id: "", name: name, items: items)
    }
}

private func item(_ id: String, _ sets: Int, _ reps: Int, rest: Int = 90, or alternatives: [String] = []) -> RoutineItem {
    RoutineItem(exerciseId: id, sets: sets, reps: reps, weightKg: nil, restSeconds: rest,
                alternativeIds: alternatives)
}

let routineLibrary: [RoutineProgram] = [
    RoutineProgram(
        id: "full-body",
        name: "Cuerpo completo",
        shortName: "Cuerpo completo",
        level: .beginner,
        daysPerWeek: "3 días",
        summary: "Dos sesiones que se alternan (A, B, A…), con un día de descanso entre cada una. "
            + "Trabaja todo el cuerpo cada vez: lo más eficaz para empezar.",
        days: [
            ProgramDay(name: "A", items: [
                item("squat", 3, 8, rest: 150, or: ["leg-press", "goblet-squat"]),
                item("bench-press", 3, 8, rest: 150, or: ["db-bench-press", "machine-chest-press"]),
                item("seated-row", 3, 10, or: ["machine-row"]),
                item("db-shoulder-press", 2, 10, or: ["machine-shoulder-press"]),
                item("leg-curl", 2, 12, rest: 60, or: ["seated-leg-curl"]),
                item("crunch", 2, 15, rest: 60),
            ]),
            ProgramDay(name: "B", items: [
                item("rdl", 3, 8, rest: 150, or: ["db-rdl"]),
                item("incline-db-press", 3, 10, or: ["machine-incline-press"]),
                item("lat-pulldown", 3, 10, or: ["machine-pulldown", "assisted-pull-up"]),
                item("lunge", 2, 10, or: ["db-split-squat"]),
                item("lateral-raise", 2, 15, rest: 60, or: ["cable-lateral-raise", "machine-lateral-raise"]),
                item("hanging-leg-raise", 2, 12, rest: 60, or: ["lying-leg-raise"]),
            ]),
        ]
    ),
    RoutineProgram(
        id: "ppl",
        name: "Empuje, tirón y pierna",
        shortName: "PPL",
        level: .intermediate,
        daysPerWeek: "3 o 6 días",
        summary: "Cada día un tipo de movimiento: empujar (pecho, hombros, tríceps), tirar (espalda, "
            + "bíceps) y pierna. Una vuelta por semana, o dos si entrenas seis días.",
        days: [
            ProgramDay(name: "Empuje", items: [
                item("bench-press", 4, 6, rest: 180, or: ["smith-bench-press", "machine-chest-press"]),
                item("overhead-press", 3, 8, rest: 150, or: ["db-shoulder-press", "machine-shoulder-press"]),
                item("incline-db-press", 3, 10, or: ["machine-incline-press"]),
                item("cable-lateral-raise", 3, 15, rest: 60, or: ["lateral-raise", "machine-lateral-raise"]),
                item("cable-fly", 3, 12, rest: 60, or: ["pec-deck"]),
                item("rope-pushdown", 3, 12, rest: 60, or: ["triceps-pushdown"]),
            ]),
            ProgramDay(name: "Tirón", items: [
                item("deadlift", 3, 5, rest: 180, or: ["rack-pull"]),
                item("pull-up", 3, 8, rest: 150, or: ["lat-pulldown", "assisted-pull-up"]),
                item("barbell-row", 3, 8, rest: 120, or: ["t-bar-row", "machine-row"]),
                item("face-pull", 3, 15, rest: 60, or: ["machine-reverse-fly"]),
                item("barbell-curl", 3, 10, rest: 60, or: ["ez-curl", "cable-curl"]),
                item("hammer-curl", 2, 12, rest: 60, or: ["cable-hammer-curl"]),
            ]),
            ProgramDay(name: "Pierna", items: [
                item("squat", 4, 6, rest: 180, or: ["hack-squat", "smith-squat"]),
                item("rdl", 3, 8, rest: 150, or: ["db-rdl"]),
                item("leg-press", 3, 12, rest: 120),
                item("seated-leg-curl", 3, 12, rest: 60, or: ["leg-curl"]),
                item("leg-extension", 3, 15, rest: 60),
                item("calf-raise", 4, 12, rest: 60, or: ["seated-calf-raise", "calf-press"]),
            ]),
        ]
    ),
    RoutineProgram(
        id: "upper-lower",
        name: "Torso y pierna",
        shortName: "Torso/Pierna",
        level: .intermediate,
        daysPerWeek: "4 días",
        summary: "Torso, pierna, descanso, torso, pierna. Cada músculo dos veces por semana: el día A "
            + "más pesado, el B con más repeticiones.",
        days: [
            ProgramDay(name: "Torso A", items: [
                item("bench-press", 4, 6, rest: 180, or: ["db-bench-press"]),
                item("barbell-row", 4, 6, rest: 150, or: ["pendlay-row", "t-bar-row"]),
                item("overhead-press", 3, 8, rest: 120, or: ["db-shoulder-press"]),
                item("lat-pulldown", 3, 10, or: ["pull-up"]),
                item("skull-crusher", 2, 10, rest: 60, or: ["db-lying-extension"]),
                item("barbell-curl", 2, 10, rest: 60, or: ["ez-curl"]),
            ]),
            ProgramDay(name: "Pierna A", items: [
                item("squat", 4, 6, rest: 180, or: ["hack-squat"]),
                item("rdl", 3, 8, rest: 150),
                item("db-split-squat", 3, 10, or: ["lunge"]),
                item("leg-curl", 3, 10, rest: 60, or: ["seated-leg-curl"]),
                item("calf-raise", 4, 10, rest: 60),
            ]),
            ProgramDay(name: "Torso B", items: [
                item("incline-db-press", 3, 10, or: ["machine-incline-press"]),
                item("seated-row", 3, 12, or: ["machine-row"]),
                item("machine-chest-press", 3, 12, or: ["cable-chest-press"]),
                item("neutral-pulldown", 3, 12, or: ["machine-pulldown"]),
                item("lateral-raise", 3, 15, rest: 60, or: ["cable-lateral-raise", "machine-lateral-raise"]),
                item("rope-pushdown", 3, 12, rest: 60),
                item("incline-db-curl", 3, 12, rest: 60, or: ["cable-curl"]),
            ]),
            ProgramDay(name: "Pierna B", items: [
                item("leg-press", 4, 12, rest: 120),
                item("hip-thrust", 3, 10, rest: 120, or: ["glute-bridge"]),
                item("leg-extension", 3, 15, rest: 60),
                item("seated-leg-curl", 3, 15, rest: 60, or: ["leg-curl"]),
                item("seated-calf-raise", 4, 15, rest: 60, or: ["calf-raise"]),
                item("cable-crunch", 3, 15, rest: 60, or: ["machine-crunch"]),
            ]),
        ]
    ),
    RoutineProgram(
        id: "upper-lower-ppl",
        name: "Torso, pierna y PPL",
        shortName: "UL/PPL",
        level: .intermediate,
        daysPerWeek: "5 días",
        summary: "Lunes torso, martes pierna, miércoles descanso, jueves empuje, viernes tirón y sábado "
            + "pierna. Cada músculo dos veces por semana, con los básicos pesados al principio y "
            + "aislamientos después.",
        days: [
            ProgramDay(name: "Torso", items: [
                item("incline-bench-press", 3, 8, rest: 150,
                     or: ["incline-db-press", "smith-incline-press", "machine-incline-press"]),
                item("pec-deck", 3, 12, rest: 60, or: ["cable-fly"]),
                item("pull-up", 3, 8, rest: 150, or: ["assisted-pull-up", "lat-pulldown"]),
                item("cable-lateral-raise", 3, 12, rest: 60, or: ["lateral-raise", "machine-lateral-raise"]),
                item("barbell-row", 3, 8, rest: 120, or: ["pendlay-row"]),
                item("cable-overhead-extension", 3, 12, rest: 60,
                     or: ["db-overhead-extension", "barbell-overhead-extension"]),
                item("preacher-curl", 3, 12, rest: 60, or: ["machine-preacher-curl", "db-preacher-curl"]),
            ]),
            ProgramDay(name: "Pierna A", items: [
                item("leg-curl", 3, 10, rest: 90),
                item("squat", 3, 6, rest: 180, or: ["smith-squat", "hack-squat"]),
                item("rdl", 3, 8, rest: 150, or: ["db-rdl"]),
                item("leg-extension", 3, 12, rest: 60),
                item("hip-abduction", 3, 15, rest: 60),
                item("calf-raise", 3, 12, rest: 60, or: ["seated-calf-raise", "calf-press"]),
            ]),
            ProgramDay(name: "Empuje", items: [
                item("bench-press", 3, 6, rest: 180, or: ["smith-bench-press"]),
                item("machine-shoulder-press", 3, 10, rest: 120, or: ["db-shoulder-press"]),
                item("pec-deck", 3, 12, rest: 60, or: ["cable-fly"]),
                item("cable-lateral-raise", 3, 12, rest: 60, or: ["lateral-raise", "machine-lateral-raise"]),
                item("cable-overhead-extension", 3, 12, rest: 60, or: ["db-overhead-extension"]),
                item("cable-kickback", 3, 12, rest: 60, or: ["db-kickback"]),
            ]),
            ProgramDay(name: "Tirón", items: [
                item("neutral-pulldown", 3, 10, rest: 120, or: ["lat-pulldown"]),
                item("t-bar-row", 3, 8, rest: 120),
                item("seated-row", 3, 10, rest: 90, or: ["rope-seated-row"]),
                item("machine-reverse-fly", 3, 15, rest: 60, or: ["cable-reverse-fly", "db-reverse-fly"]),
                item("barbell-shrug", 3, 12, rest: 60, or: ["db-shrug"]),
                item("ez-curl", 3, 10, rest: 60),
                item("preacher-curl", 3, 12, rest: 60, or: ["machine-preacher-curl", "db-preacher-curl"]),
            ]),
            ProgramDay(name: "Pierna B", items: [
                item("seated-leg-curl", 3, 10, rest: 90),
                item("squat", 3, 8, rest: 180, or: ["smith-squat", "hack-squat"]),
                item("leg-extension", 3, 12, rest: 60),
                item("hip-abduction", 3, 15, rest: 60),
                item("calf-raise", 3, 12, rest: 60, or: ["seated-calf-raise", "calf-press"]),
            ]),
        ]
    ),
    RoutineProgram(
        id: "strength-5x5",
        name: "Fuerza 5 × 5",
        shortName: "5×5",
        level: .beginner,
        daysPerWeek: "3 días",
        summary: "Pocos ejercicios con barra, cinco series de cinco. Alterna A y B, y sube un poco el peso "
            + "cada vez que completas todas las series.",
        days: [
            ProgramDay(name: "A", items: [
                item("squat", 5, 5, rest: 180),
                item("bench-press", 5, 5, rest: 180),
                item("barbell-row", 5, 5, rest: 180, or: ["pendlay-row"]),
            ]),
            ProgramDay(name: "B", items: [
                item("squat", 5, 5, rest: 180),
                item("overhead-press", 5, 5, rest: 180),
                item("deadlift", 1, 5, rest: 180),
            ]),
        ]
    ),
    RoutineProgram(
        id: "bro-split",
        name: "Un grupo por día",
        shortName: "Split",
        level: .intermediate,
        daysPerWeek: "5 días",
        summary: "El reparto clásico de culturismo: pecho, espalda, pierna, hombros y brazos, cada uno "
            + "en su día, con mucho volumen por músculo.",
        days: [
            ProgramDay(name: "Pecho", items: [
                item("bench-press", 4, 8, rest: 150, or: ["smith-bench-press"]),
                item("incline-db-press", 4, 10, or: ["smith-incline-press", "machine-incline-press"]),
                item("machine-chest-press", 3, 12),
                item("pec-deck", 3, 12, rest: 60, or: ["cable-fly", "db-fly"]),
                item("dips", 3, 10, or: ["machine-dip"]),
            ]),
            ProgramDay(name: "Espalda", items: [
                item("pull-up", 4, 8, rest: 150, or: ["assisted-pull-up", "lat-pulldown"]),
                item("barbell-row", 4, 8, rest: 120, or: ["t-bar-row"]),
                item("seated-row", 3, 12, or: ["machine-row"]),
                item("db-row", 3, 10),
                item("straight-arm-pulldown", 3, 15, rest: 60),
                item("hyperextension", 3, 12, rest: 60, or: ["machine-back-extension"]),
            ]),
            ProgramDay(name: "Pierna", items: [
                item("squat", 4, 8, rest: 180, or: ["hack-squat"]),
                item("leg-press", 4, 12, rest: 120),
                item("rdl", 3, 10, rest: 120),
                item("leg-extension", 3, 15, rest: 60),
                item("leg-curl", 3, 12, rest: 60, or: ["seated-leg-curl"]),
                item("calf-raise", 4, 15, rest: 60, or: ["seated-calf-raise"]),
            ]),
            ProgramDay(name: "Hombros", items: [
                item("seated-overhead-press", 4, 8, rest: 150, or: ["db-shoulder-press", "machine-shoulder-press"]),
                item("arnold-press", 3, 10),
                item("lateral-raise", 4, 15, rest: 60, or: ["cable-lateral-raise", "machine-lateral-raise"]),
                item("db-reverse-fly", 3, 15, rest: 60, or: ["machine-reverse-fly", "face-pull"]),
                item("db-shrug", 3, 12, rest: 60, or: ["barbell-shrug"]),
            ]),
            ProgramDay(name: "Brazos", items: [
                item("close-grip-bench-press", 3, 8, rest: 120),
                item("barbell-curl", 3, 10, rest: 60, or: ["ez-curl"]),
                item("skull-crusher", 3, 10, rest: 60),
                item("incline-db-curl", 3, 12, rest: 60),
                item("rope-pushdown", 3, 12, rest: 60, or: ["triceps-pushdown"]),
                item("hammer-curl", 3, 12, rest: 60, or: ["cable-hammer-curl"]),
            ]),
        ]
    ),
    RoutineProgram(
        id: "home-bodyweight",
        name: "En casa sin equipo",
        shortName: "En casa",
        level: .any,
        daysPerWeek: "3 días",
        summary: "Solo con el peso del cuerpo, para cuando no hay gimnasio. Si es poco, haz las "
            + "variantes más difíciles: flexiones declinadas, sentadilla búlgara.",
        days: [
            ProgramDay(name: "Cuerpo completo", items: [
                item("push-up", 4, 12, or: ["incline-push-up", "decline-push-up"]),
                item("split-squat", 3, 12, or: ["pistol-squat"]),
                item("inverted-row", 3, 10, or: ["pull-up"]),
                item("glute-bridge", 3, 15, rest: 60),
                item("bench-dip", 3, 12, rest: 60, or: ["diamond-push-up"]),
                item("bodyweight-calf-raise", 3, 20, rest: 45),
                item("dead-bug", 3, 12, rest: 45, or: ["mountain-climber"]),
            ]),
        ]
    ),
]
