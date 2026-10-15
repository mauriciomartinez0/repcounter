"""
Port of updateStack() from rep_counter_ble.ino (profile 2, weight stack), fed
with synthetic sets: minimum-jerk strokes, accelerometer bias and noise, and a
spike where the stack lands. Keep the constants in sync with the firmware.

    python3 stack_sim.py
"""
import numpy as np

FS = 104.0; DT = 1 / FS; G = 9.80665
UP, DOWN, END = 0.12, 0.12, 0.04
TAU, DEAD = 3.0, 0.005
STILL_ALPHA, STILL_G, STILL_MS = 0.1, 0.006, 250
IDLE_MS, REFRACT = 3000, 600

def count(acc_g):
    """acc_g: vertical accelerometer reading in g (1.0 at rest, plus bias/noise)."""
    ref = np.mean(acc_g[:int(FS)])           # reference captured at rest
    v, phase, still_since, reps, last, smooth = 0.0, 0, 0, 0, -10**9, 0.0
    for i, a in enumerate(acc_g):
        now = int(i * 1000 / FS)
        vert = a - ref
        smooth += STILL_ALPHA * (vert - smooth)
        if abs(vert) < DEAD: vert = 0.0
        v += vert * G * DT
        v -= v * DT / TAU
        still = False
        if abs(smooth) < STILL_G:
            if still_since == 0: still_since = now
            if now - still_since >= STILL_MS: v = 0.0; still = True
        else:
            still_since = 0
        if phase == 0 and v > UP: phase = 1
        elif phase == 1:
            if v < -DOWN: phase = 2
            elif still and now - still_since >= IDLE_MS: phase = 0
        elif phase == 2 and v > -END:
            phase = 0
            if now - last >= REFRACT: reps += 1; last = now
    return reps

def smooth_move(dist, secs):
    """Position over `secs` for a move of `dist` metres (minimum-jerk)."""
    t = np.linspace(0, 1, max(2, int(secs * FS)))
    return dist * (10 * t**3 - 15 * t**4 + 6 * t**5)

def make_set(reps, height, up_s, top_s, down_s, rest_s, bump_g, rng, bias_g=0.015, noise_g=0.004):
    pos = [np.zeros(int(1.5 * FS))]              # still: reference capture
    for _ in range(reps):
        pos.append(smooth_move(height, up_s))
        pos.append(np.full(int(top_s * FS), height))
        pos.append(height - smooth_move(height, down_s))
        pos.append(np.zeros(int(rest_s * FS)))
    pos.append(np.zeros(int(2 * FS)))
    p = np.concatenate(pos)
    acc = np.gradient(np.gradient(p, DT), DT) / G
    # The stack lands on the rest of the pile: a short upward spike.
    landings = np.where((p[:-1] > 0.002) & (p[1:] <= 0.002))[0]
    for k in landings:
        acc[k:k + 3] += bump_g
    return 1.0 + bias_g + acc + rng.normal(0, noise_g, len(acc))

rng = np.random.default_rng(1)
cases = {
    "normal 10 reps (45 cm, 1 s up, 1.5 s down)": (10, 0.45, 1.0, 0.2, 1.5, 0.4, 0.3),
    "rápido 12 reps (35 cm, 0.6 s / 0.8 s, sin pausa)": (12, 0.35, 0.6, 0.0, 0.8, 0.05, 0.4),
    "lento 6 reps (50 cm, 2 s / 3 s, pausa arriba 1 s)": (6, 0.50, 2.0, 1.0, 3.0, 0.8, 0.2),
    "pausa larga 5 reps (pausa arriba 2,5 s)": (5, 0.45, 1.5, 2.5, 2.0, 0.8, 0.2),
    "muy lento 5 reps (4 s / 4 s)": (5, 0.50, 4.0, 0.5, 4.0, 1.0, 0.2),
    "corto 8 reps (15 cm, polea de rotación externa)": (8, 0.15, 0.8, 0.1, 1.0, 0.4, 0.15),
    "golpe fuerte al bajar 8 reps": (8, 0.40, 0.9, 0.1, 1.0, 0.3, 0.8),
}
for noise in (0.004, 0.008):
    print(f"ruido {noise * 1000:.0f} mg")
    for name, args in cases.items():
        results = [count(make_set(*args, rng, noise_g=noise)) for _ in range(20)]
        print(f"  {name}: esperadas {args[0]}, contadas {min(results)}–{max(results)}")
# Holding still, or fidgeting with the pin, must count nothing.
quiet = 1.015 + rng.normal(0, 0.004, int(20 * FS))
print("20 s quieto:", count(quiet))
