"""
Port of updateStack() from rep_counter_ble.ino (profile 2, weight stack), fed
with synthetic sets. Keep the constants in sync with the firmware.

The sets use the noise and bias measured on the board (see TRASPASO.md): about
1 mg rms of noise and 40 mg of bias, plus ringing where the stack lands. The
reference captured at rest cancels the bias along the vertical axis; whatever
is left during the set ("residual") is what the algorithm has to tolerate.

    python3 stack_sim.py

Every case is simulated; none of it replaces a recording of a real set.
"""

import numpy as np

FS = 104.0
DT = 1 / FS
G = 9.80665

# Firmware constants.
DEADBAND_MPS = 0.02
MIN_ROM_M = 0.04
GRIP_MARGIN_M = 0.02
MAX_GRIP_LIFT_CM = 30
LEAK_TAU_S = 3.0
DEADBAND_G = 0.005
STILL_ALPHA, STILL_G, STILL_MS = 0.1, 0.006, 250
IDLE_MS, REFRACTORY_MS = 3000, 600


def min_rom_for_grip(grip_cm):
    """Travel each way to be a stroke, given how far taking the handle lifts
    the stack (the app's setting)."""
    return max(MIN_ROM_M, min(grip_cm, MAX_GRIP_LIFT_CM) * 0.01 + GRIP_MARGIN_M)


def count(acc_g, min_rom=MIN_ROM_M):
    """acc_g: accelerometer reading along the vertical, in g (1.0 at rest)."""
    ref = np.mean(acc_g[: int(FS)])          # reference captured at rest
    v = smooth = rise = fall = 0.0
    phase, still_since, reps, last = 0, 0, 0, -10**9
    for i, a in enumerate(acc_g):
        now = int(i * 1000 / FS)
        vert = a - ref
        smooth += STILL_ALPHA * (vert - smooth)
        if abs(vert) < DEADBAND_G:
            vert = 0.0
        v += vert * G * DT
        v -= v * DT / LEAK_TAU_S
        still = False
        if abs(smooth) < STILL_G:
            if still_since == 0:
                still_since = now
            if now - still_since >= STILL_MS:
                v = 0.0
                still = True
        else:
            still_since = 0

        if phase == 0:                       # waiting for a lift
            if v > DEADBAND_MPS:
                rise += v * DT
            elif v < -DEADBAND_MPS or still:
                rise = 0.0
            if rise >= min_rom:
                phase, fall = 1, 0.0
        elif phase == 1:                     # lifted, waiting for the way down
            if v < -DEADBAND_MPS:
                fall += -v * DT
            elif v > DEADBAND_MPS:
                fall = 0.0
            if fall >= min_rom:
                phase = 2
            elif still and now - still_since >= IDLE_MS:
                phase, rise = 0, 0.0
        elif phase == 2 and v > -DEADBAND_MPS:   # the descent ended
            phase, rise = 0, 0.0
            if now - last >= REFRACTORY_MS:
                reps, last = reps + 1, now
    return reps


def smooth_move(dist, secs):
    """Minimum-jerk position over `secs` for a move of `dist` metres."""
    t = np.linspace(0, 1, max(2, int(secs * FS)))
    return dist * (10 * t**3 - 15 * t**4 + 6 * t**5)


def constant_velocity_move(dist, vmax, ramp=0.25):
    """Ramp up, hold vmax, ramp down: the stretch an accelerometer reads as rest."""
    hold = max(0.0, (dist - vmax * ramp) / vmax)
    vel = np.concatenate([np.linspace(0, vmax, int(ramp * FS)),
                          np.full(int(hold * FS), vmax),
                          np.linspace(vmax, 0, int(ramp * FS))])
    return np.cumsum(vel) * DT


def to_accel(strokes, rng, noise_g, bias_g, residual_g, bump_g):
    pos = np.concatenate([np.zeros(int(1.5 * FS)), *strokes, np.zeros(int(2 * FS))])
    acc = np.gradient(np.gradient(pos, DT), DT) / G
    # The stack lands: the braking is already in the stroke, so the impact
    # only adds ringing that goes both ways and leaves the velocity unchanged.
    t = np.arange(int(0.12 * FS)) * DT
    ring = bump_g * np.exp(-t / 0.03) * np.cos(2 * np.pi * 25 * t)
    ring -= ring.mean()
    for k in np.where((pos[:-1] > 0.002) & (pos[1:] <= 0.002))[0]:
        acc[k:k + len(ring)] += ring[: len(acc) - k]
    out = 1.0 + bias_g + acc + rng.normal(0, noise_g, len(acc))
    out[int(1.5 * FS):] += residual_g          # bias the reference does not cancel
    return out


def degrading_set(rng, n=10, h0=0.45, h1=0.22, up0=1.0, up1=2.4, down=1.5, top=0.15,
                  rest=0.4, noise_g=0.00106, bias_g=0.040, residual_g=0.0, bump_g=0.3):
    """A set taken towards failure: range shrinks and the lift slows down."""
    strokes = []
    for i in range(n):
        f = i / (n - 1) if n > 1 else 0.0
        h, up = h0 + (h1 - h0) * f, up0 + (up1 - up0) * f
        strokes += [smooth_move(h, up), np.full(int(top * FS), h),
                    h - smooth_move(h, down), np.zeros(int(rest * FS))]
    return to_accel(strokes, rng, noise_g, bias_g, residual_g, bump_g)


def constant_velocity_set(rng, n=8, h=0.45, vmax=0.5, rest=0.5, residual_g=0.0):
    strokes = []
    for _ in range(n):
        up = constant_velocity_move(h, vmax)
        strokes += [up, np.full(int(0.15 * FS), up[-1]), up[-1] - constant_velocity_move(h, vmax),
                    np.zeros(int(rest * FS))]
    return to_accel(strokes, rng, 0.00106, 0.040, residual_g, 0.3)


def fidgeting(rng, seconds=20):
    """Nudging the stack 2 cm three times while adjusting the grip."""
    pos = np.zeros(int(seconds * FS))
    m = smooth_move(0.02, 0.4)
    for t0 in (3, 8, 13):
        k = int(t0 * FS)
        pos[k:k + len(m)] = m
        pos[k + len(m):k + 2 * len(m)] = 0.02 - m
    return 1.04 + np.gradient(np.gradient(pos, DT), DT) / G + rng.normal(0, 0.00106, len(pos))


def gripped_set(rng, grip=0.06, n=8, h=0.40, regrips=1, residual_g=0.0):
    """Taking the handle lifts the stack `grip` metres and the user holds it
    there; letting go and taking it again (`regrips`) drops it and lifts it
    again. Then `n` reps that come back to the grip height, and letting go."""
    take = smooth_move(grip, 0.3)
    strokes = [take, np.full(int(1.0 * FS), grip)]
    for _ in range(regrips):
        strokes += [grip - take, np.zeros(int(0.6 * FS)), take, np.full(int(1.0 * FS), grip)]
    for _ in range(n):
        up = smooth_move(h, 1.0)
        strokes += [grip + up, np.full(int(0.15 * FS), grip + h), grip + h - up,
                    np.full(int(0.4 * FS), grip)]
    strokes.append(grip - take)
    return to_accel(strokes, rng, 0.00106, 0.040, residual_g, 0.3)


GRIP_CASES = {
    "agarrar y soltar 3 veces, sin reps": (0, {"n": 0, "regrips": 3}),
    "agarrar, 8 reps sin soltar, soltar": (8, {"regrips": 0}),
    "agarrar, reacomodar, 8 reps, soltar": (8, {}),
}

CASES = {
    "al fallo, 45→22 cm, subida 1→2,4 s": (10, {}),
    "al fallo con vibración (4 mg)": (10, {"noise_g": 0.004}),
    "al fallo sin descanso abajo": (10, {"rest": 0.1}),
    "rápida, 0,6 s / 0,8 s": (12, {"h0": 0.35, "h1": 0.35, "up0": 0.6, "up1": 0.6, "down": 0.8, "top": 0.0, "rest": 0.05}),
    "tempo lento 4 s / 4 s, al fallo": (6, {"up0": 4.0, "up1": 4.0, "down": 4.0}),
    "tempo lento 4 s / 4 s, 50 cm": (6, {"h0": 0.5, "h1": 0.5, "up0": 4.0, "up1": 4.0, "down": 4.0}),
    "pausa de 2,5 s arriba": (5, {"top": 2.5}),
    "parciales de 8 cm": (8, {"h0": 0.08, "h1": 0.08, "up0": 0.6, "up1": 0.6, "down": 0.8}),
    "recorrido corto 15 cm": (8, {"h0": 0.15, "h1": 0.15, "up0": 0.8, "up1": 0.8, "down": 1.0}),
    "golpe fuerte al asentar": (8, {"bump_g": 0.8}),
}

if __name__ == "__main__":
    rng = np.random.default_rng(7)
    for residual in (0.0, 0.0005, -0.0005, 0.001, -0.001):
        print(f"sesgo residual {residual * 1000:+.1f} mg")
        for name, (n, kw) in CASES.items():
            r = [count(degrading_set(rng, n=n, residual_g=residual, **kw)) for _ in range(10)]
            mark = "" if min(r) == max(r) == n else "   ✗"
            print(f"  {name}: {n} → {min(r)}–{max(r)}{mark}")
        for vmax in (0.5, 0.8):
            r = [count(constant_velocity_set(rng, vmax=vmax, residual_g=residual)) for _ in range(10)]
            mark = "" if min(r) == max(r) == 8 else "   ✗"
            print(f"  velocidad constante {vmax} m/s (trampa 6.3): 8 → {min(r)}–{max(r)}{mark}")
    print("quieto 20 s:", count(1.04 + rng.normal(0, 0.00106, int(20 * FS))))
    print("reacomodar el agarre (3 empujones de 2 cm):", count(fidgeting(rng)))
    # The stack rises when the handle is taken: without the app's setting
    # (4 cm minimum) and with it set to the real lift.
    for grip_cm in (3, 6, 10):
        print(f"la pila sube {grip_cm} cm al agarrar")
        for name, (n, kw) in GRIP_CASES.items():
            sets = [gripped_set(rng, grip=grip_cm / 100, **kw) for _ in range(10)]
            for label, rom in (("sin ajuste", MIN_ROM_M), (f"ajuste {grip_cm} cm", min_rom_for_grip(grip_cm))):
                r = [count(a, rom) for a in sets]
                mark = "" if min(r) == max(r) == n else "   ✗"
                print(f"  {name}, {label}: {n} → {min(r)}–{max(r)}{mark}")
