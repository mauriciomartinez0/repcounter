"""
Port of updateStack() from rep_counter_ble.ino (profile 2, weight stack), fed
with synthetic sets. Keep the constants in sync with the firmware.

The count follows the period of the height curve (Periodic): no minimum
travel to configure, so the grip cases run with nothing set.

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
LEAK_TAU_S = 3.0
DEADBAND_G = 0.005
STILL_ALPHA, STILL_G, STILL_MS = 0.1, 0.006, 250
# Counting by the period of the height curve. Each threshold goes from
# strict (sensitivity 0) through the default (50) to lenient (100); the app
# sets the sensitivity live with a slider.
TUNING = {
    #                 strict  default  lenient
    "turn_m":         (0.03,  0.02,    0.01),   # the height has to come back this much to be a turn
    "min_amp_m":      (0.05,  0.03,    0.015),  # smaller waves are noise, nudges, the landing bump
    "similar_amp":    (0.5,   0.35,    0.2),    # first two reps: amplitude ratio...
    "similar_period": (0.6,   0.5,     0.35),   # ...and period ratio
    "amp_fraction":   (0.5,   0.3,     0.15),   # then: this much of the usual amplitude, or
    "fade_fraction":  (0.8,   0.6,     0.3),    # this much of the last rep (a set to failure shrinks)...
    "period_min":     (0.5,   1 / 3,   0.3),    # ...and a period within this of the usual one
    "period_max":     (2.0,   3.0,     5.0),
    "settled":        (0.8,   0.5,     0.25),   # resting counts as the bottom only this far down
}
NEAR_M = 0.01          # still at the bottom: the rep has not left yet
SETTLE_MS = 800        # resting this long closes a wave: a slow stroke reads as rest midway
HISTORY = 5
PENDING = 3            # waves kept while waiting for the first pair
DEFAULT_SENSITIVITY = 50


def tuning(sensitivity=DEFAULT_SENSITIVITY):
    """The thresholds for a sensitivity of 0–100. 50 gives the defaults exactly."""
    s = min(100, max(0, sensitivity))
    out = {}
    for key, (strict, mid, lenient) in TUNING.items():
        if s < 50:
            out[key] = mid + (strict - mid) * (50 - s) / 50
        else:
            out[key] = mid + (lenient - mid) * (s - 50) / 50
    return out


class Periodic:
    """Which waves are reps: the ones that repeat. The first one waits for a
    second one like it, among the last few waves (then both count); after that a wave counts when its
    period is close to the usual one and it is not much smaller. Shared with
    the end-of-set analysis (set_analysis.py, pass A)."""

    def __init__(self, t=None):
        self.t = t or tuning()
        self.pending = []
        self.history = []
        self.reps = 0

    def add(self, amp, period):
        """amp in m, period in s. Returns how many reps this wave added."""
        t = self.t
        if amp < t["min_amp_m"] or period <= 0:
            return 0
        c = (amp, period)
        if not self.history:
            for p in reversed(self.pending):
                if (min(p[0], amp) / max(p[0], amp) >= t["similar_amp"]
                        and min(p[1], period) / max(p[1], period) >= t["similar_period"]):
                    self.history = [p, c]
                    self.pending = []
                    self.reps += 2
                    return 2
            self.pending = (self.pending + [c])[-PENDING:]
            return 0
        amps = sorted(x[0] for x in self.history)
        periods = sorted(x[1] for x in self.history)
        ref_amp, ref_period = amps[len(amps) // 2], periods[len(periods) // 2]
        if ((amp >= t["amp_fraction"] * ref_amp or amp >= t["fade_fraction"] * self.history[-1][0])
                and t["period_min"] * ref_period <= period <= t["period_max"] * ref_period):
            self.history = (self.history + [c])[-HISTORY:]
            self.reps += 1
            return 1
        return 0


def count(acc_g, sensitivity=DEFAULT_SENSITIVITY):
    """acc_g: accelerometer reading along the vertical, in g (1.0 at rest)."""
    t = tuning(sensitivity)
    ref = np.mean(acc_g[: int(FS)])          # reference captured at rest
    v = smooth = h = 0.0
    still_since = 0
    rising = True
    trough = peak = 0.0
    depart = arrive = 0
    waves = Periodic(t)

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
        h += v * DT

        if rising:
            if h < trough:
                trough = h
            if h <= trough + NEAR_M:
                depart, peak = now, h
            peak = max(peak, h)
            if h <= peak - t["turn_m"]:      # turned at the top
                rising, bottom, arrive = False, h, now
        else:
            if h < bottom:
                bottom, arrive = h, now
            settled = (still and now - still_since >= SETTLE_MS
                       and peak - bottom >= t["settled"] * (peak - trough))
            if h >= bottom + t["turn_m"] or settled:
                # Turned at the bottom, or came to rest there: a full wave. A
                # rest higher up is a pause at the top, not the end of it.
                waves.add((2 * peak - trough - bottom) / 2, (arrive - depart) / 1000)
                rising, trough, peak, depart = True, bottom, h, now
    return waves.reps


# Tilt profiles (sensor on the arm, the body or a bar): the same waves, on the
# angle from the calibration pose instead of the height. The thresholds in
# degrees follow the stack's from the same sensitivity.
TILT_TURN_DEG_PER_M = 450      # 2 cm -> 9°
TILT_AMP_DEG_PER_M = 500       # 3 cm -> 15°


def tilt_tuning(sensitivity=DEFAULT_SENSITIVITY):
    t = tuning(sensitivity)
    t["turn_m"] *= TILT_TURN_DEG_PER_M
    t["min_amp_m"] *= TILT_AMP_DEG_PER_M
    return t


def count_tilt(times_ms, angles_deg, sensitivity=DEFAULT_SENSITIVITY):
    """The tilt counter (TiltCounter in set_analysis.h) over an angle series.
    A wave closes when the angle turns up again, or when it stays put near
    the bottom for SETTLE_MS after coming at least `settled` of the way down:
    the arm does not have to get back to the calibration pose."""
    t = tilt_tuning(sensitivity)
    waves = Periodic(t)
    rising = True
    trough = peak = bottom = angles_deg[0]
    depart = arrive = flat_since = times_ms[0]
    for now, h in zip(times_ms, angles_deg):
        if rising:
            if h < trough:
                trough = h
            if h <= trough + t["turn_m"] / 2:
                depart, peak = now, h
            peak = max(peak, h)
            if h <= peak - t["turn_m"]:
                rising, bottom, arrive, flat_since = False, h, now, now
        else:
            if h < bottom:
                bottom, arrive = h, now
            if h > bottom + t["turn_m"] / 2 or h < bottom - t["turn_m"] / 2:
                flat_since = now
            settled = (now - flat_since >= SETTLE_MS
                       and peak - bottom >= t["settled"] * (peak - trough))
            if h >= bottom + t["turn_m"] or settled:
                waves.add((2 * peak - trough - bottom) / 2, (arrive - depart) / 1000)
                rising, trough, peak, depart = True, bottom, h, now
    return waves.reps


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


def hand_set(rng, n=10, amp=0.30, period=1.6, tilt_offset_deg=10.0, wobble_deg=10.0,
             rest_s=1.5, sway=0.03, vertical=None):
    """Held in the hand, to try it without a machine: continuous up and down,
    the wrist tilts with the movement, the hand holds it some degrees off the
    pose it calibrated in and sways a little sideways. Simulated in 3D with
    the board's bias (40 mg) and turned into the vertical signal the firmware
    computes (`vertical`, default VERTICAL)."""
    t = np.arange(int((rest_s + n * period + 1.0) * FS)) * DT
    z, y, tilt = np.zeros_like(t), np.zeros_like(t), np.zeros_like(t)
    m = (t >= rest_s) & (t < rest_s + n * period)
    ph = (t[m] - rest_s) / period
    z[m] = amp * (1 - np.cos(2 * np.pi * ph)) / 2
    ramp = np.minimum(1, (t[m] - rest_s) / 0.6)
    y[m] = sway * ramp**2 * (3 - 2 * ramp) * np.sin(2 * np.pi * ph + 1.3)   # eases in
    tilt[m] = (np.radians(tilt_offset_deg) * np.minimum(1, (t[m] - rest_s) / 0.3)
               + np.radians(wobble_deg) * np.sin(2 * np.pi * ph + 0.7))
    az = np.gradient(np.gradient(z, DT), DT) / G + 1.0      # world frame, in g
    ay = np.gradient(np.gradient(y, DT), DT) / G
    # Rotate the world vector into the sensor frame (tilt about x).
    c, s_ = np.cos(tilt), np.sin(tilt)
    sy = c * ay + s_ * az
    sz = -s_ * ay + c * az
    bias = np.array([0.020, -0.028, 0.020])                  # 40 mg
    acc = np.stack([np.zeros_like(t), sy, sz], 1) + bias + rng.normal(0, 0.00106, (len(t), 3))
    return vertical_signal(acc, vertical)


def vertical_signal(acc3, method=None):
    """What updateStack() feeds the counter, from raw 3-axis readings in g:
    the magnitude (does not care how the sensor is turned), or the old
    projection on the axis that was vertical at calibration."""
    method = method or VERTICAL
    ref = acc3[: int(FS)].mean(0)
    if method == "projection":
        return acc3 @ ref / np.linalg.norm(ref)
    return np.linalg.norm(acc3, axis=1)


VERTICAL = "magnitude"


HAND_CASES = {
    "en la mano, recto": (10, {"tilt_offset_deg": 0, "wobble_deg": 0}),
    "en la mano, 10° torcido y ±10°": (10, {}),
    "en la mano, 20° torcido y ±15°": (10, {"tilt_offset_deg": 20, "wobble_deg": 15}),
    "en la mano, lento (3 s) y 10° torcido": (8, {"n": 8, "period": 3.0}),
    "en la mano, rápido (0,9 s) y 10° torcido": (12, {"n": 12, "period": 0.9, "amp": 0.2}),
}


def uneven_set(rng, ranges, up=1.0, down=1.2, base=None, residual_g=0.0):
    """Reps of different range: `ranges` in metres, one per rep. With `base`,
    the stack does not go back to the start between reps but to that height
    (metres), and only to 0 after the last one."""
    strokes, at = [], 0.0
    for i, h in enumerate(ranges):
        low = 0.0 if base is None or i == len(ranges) - 1 else base
        top = max(h, at + 0.02)
        strokes += [at + (top - at) * smooth_move(1.0, up), np.full(int(0.1 * FS), top),
                    top - (top - low) * smooth_move(1.0, down), np.full(int(0.3 * FS), low)]
        at = low
    return to_accel(strokes, rng, 0.00106, 0.040, residual_g, 0.3)


UNEVEN_CASES = {
    "8 reps, la mitad cortas (45 y 15 cm)": (8, {"ranges": [0.45, 0.15] * 4}),
    "8 reps, la mitad muy cortas (45 y 8 cm)": (8, {"ranges": [0.45, 0.08] * 4}),
    "8 reps sin volver abajo (45 cm, bajan a 30)": (8, {"ranges": [0.45] * 8, "base": 0.30}),
}


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
    print("en la mano (sin máquina)")
    for name, (n, kw) in HAND_CASES.items():
        r = [count(hand_set(rng, **kw)) for _ in range(10)]
        mark = "" if min(r) == max(r) == n else "   ✗"
        print(f"  {name}: {n} → {min(r)}–{max(r)}{mark}")
    print("quieto 20 s:", count(1.04 + rng.normal(0, 0.00106, int(20 * FS))))
    print("reacomodar el agarre (3 empujones de 2 cm):", count(fidgeting(rng)))
    # The stack rises when the handle is taken; nothing is configured.
    for grip_cm in (3, 6, 10):
        print(f"la pila sube {grip_cm} cm al agarrar")
        for name, (n, kw) in GRIP_CASES.items():
            r = [count(gripped_set(rng, grip=grip_cm / 100, **kw)) for _ in range(10)]
            mark = "" if min(r) == max(r) == n else "   ✗"
            print(f"  {name}: {n} → {min(r)}–{max(r)}{mark}")
