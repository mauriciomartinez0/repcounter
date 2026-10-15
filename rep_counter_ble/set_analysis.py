"""
End-of-set analysis for the weight-stack profile (level 3 of TRASPASO.md).

Reference implementation of set_analysis.h: same steps, same constants. The
firmware records the vertical acceleration of the whole set and, when the set
closes, runs this over it to find reps the live counter missed. The result
only ever adds reps: the app offers the difference when it is above the live
count, and the user confirms it.

Two passes, and the set gets the larger count:

  A. The pipeline of TRASPASO.md:
       rest windows -> residual bias out -> integrate to velocity with ZUPT
       anchored on the edges of each rest window -> 4th-order Butterworth,
       forward and backward (zero phase) -> excursions of the velocity sign,
       merged and filtered by travel -> an up followed by a down is one rep.

  B. The live counter (StackCounter) run again over the recording, with the
     residual bias measured in every long rest and interpolated in time.
     Live, that bias is unknown; at the end of the set it is not.

Rest detection differs from the document on one point. The document tests
the rolling standard deviation only, and a smooth stroke barely varies over
0.2 s: on a set taken to failure it called 59 % of the set rest and the ZUPT
erased the reps (trap 6.3, wider than the document says). Rest here also
needs the mean acceleration to be near zero.

Simulated with stack_sim.py over 672 sets: the live count plus what this
adds never went above the true count, was exact with up to ±0.5 mg of
residual bias, and recovered missed reps in 12 sets. At ±1 mg and beyond it
can still be one short on a slow set taken to failure.

Run it to check it against the simulated sets in stack_sim.py:

    python3 set_analysis.py
"""

import numpy as np

FS = 104.0
DT = 1.0 / FS
G = 9.80665

# Section 8 of TRASPASO.md, plus the mean test. All need real sets to confirm.
QUIET_WINDOW_S = 0.20
QUIET_THRESH_MS2 = 0.15          # standard deviation
QUIET_MEAN_MS2 = 0.02            # pass A: |mean| below this as well
QUIET_MIN_LEN_S = 0.40
LONG_REST_MEAN_MS2 = 0.05        # pass B: rests used to measure the bias
LONG_REST_MIN_S = 1.0
DEADBAND_FRAC = 0.05
MERGE_GAP_S = 0.30
MIN_ROM_M = 0.04

# butter(4, 2.0, fs=104.0, output="sos")
SOS = (
    (1.1431134452625980e-05, 2.2862268905251960e-05, 1.1431134452625980e-05,
     -1.7864735976669488e+00, 7.9959466897088638e-01),
    (1.0, 2.0, 1.0, -1.8978737830369070e+00, 9.1181305270516411e-01),
)


def quiet_runs(acc, mean_limit=QUIET_MEAN_MS2, min_len_s=QUIET_MIN_LEN_S):
    """[start, end] (inclusive) of every stretch at rest, in samples."""
    n = len(acc)
    half = int(QUIET_WINDOW_S * FS) // 2
    # Rolling mean and standard deviation over a centred window.
    c1 = np.concatenate([[0.0], np.cumsum(acc)])
    c2 = np.concatenate([[0.0], np.cumsum(acc * acc)])
    quiet = np.zeros(n, dtype=bool)
    for i in range(n):
        lo, hi = max(0, i - half), min(n, i + half + 1)
        m = hi - lo
        mean = (c1[hi] - c1[lo]) / m
        var = max(0.0, (c2[hi] - c2[lo]) / m - mean * mean)
        quiet[i] = var < QUIET_THRESH_MS2 ** 2 and abs(mean) < mean_limit
    runs, i, min_len = [], 0, int(min_len_s * FS)
    while i < n:
        if quiet[i]:
            j = i
            while j + 1 < n and quiet[j + 1]:
                j += 1
            if j - i + 1 >= min_len:
                runs.append((i, j))
            i = j + 1
        else:
            i += 1
    return runs


def zupt_velocity(acc, runs):
    """Velocity with the drift taken out between rest anchors."""
    n = len(acc)
    if runs:
        rest = np.concatenate([acc[s:e + 1] for s, e in runs])
        acc = acc - rest.mean()                 # residual bias
    v = np.cumsum(acc) * DT
    out = v.copy()
    # Anchors: the buffer starts at rest (v = 0), then both edges of each run.
    prev_i, prev_v = 0, 0.0
    for s, e in runs:
        if s > prev_i:
            span = s - prev_i
            for i in range(prev_i, s + 1):
                out[i] = v[i] - (prev_v + (v[s] - prev_v) * (i - prev_i) / span)
        out[s:e + 1] = 0.0
        prev_i, prev_v = e, v[e]
    # After the last rest window there is no anchor ahead: only the offset.
    out[prev_i:] = v[prev_i:] - prev_v
    if runs:
        out[runs[-1][0]:runs[-1][1] + 1] = 0.0
    return out


def sosfilt(x):
    y = np.array(x, dtype=float)
    for b0, b1, b2, a1, a2 in SOS:
        z1 = z2 = 0.0                            # transposed direct form II
        for i in range(len(y)):
            xi = y[i]
            yi = b0 * xi + z1
            z1 = b1 * xi - a1 * yi + z2
            z2 = b2 * xi - a2 * yi
            y[i] = yi
    return y


def filtfilt(x):
    return sosfilt(sosfilt(x)[::-1])[::-1]


def count_reps(v):
    """Excursions of the velocity sign -> reps. Also returns the excursions."""
    n = len(v)
    p99 = np.percentile(np.abs(v), 99) if n else 0.0
    db = DEADBAND_FRAC * p99
    # Contiguous stretches above / below the deadband: [sign, start, end, travel].
    exc, i = [], 0
    while i < n:
        s = 1 if v[i] > db else (-1 if v[i] < -db else 0)
        if s == 0:
            i += 1
            continue
        j, travel = i, 0.0
        while j < n and (v[j] > db if s > 0 else v[j] < -db):
            travel += abs(v[j]) * DT
            j += 1
        exc.append([s, i, j - 1, travel])
        i = j
    gap = int(MERGE_GAP_S * FS)

    def merge(items):
        out = []
        for e in items:
            if out and out[-1][0] == e[0] and e[1] - out[-1][2] <= gap:
                out[-1][2], out[-1][3] = e[2], out[-1][3] + e[3]
            else:
                out.append(list(e))
        return out

    exc = merge(exc)
    exc = [e for e in exc if e[3] >= MIN_ROM_M]       # grip adjustments out
    # With the small ones gone, same-sign neighbours belong together.
    joined = []
    for e in exc:
        if joined and joined[-1][0] == e[0]:
            joined[-1][2], joined[-1][3] = e[2], joined[-1][3] + e[3]
        else:
            joined.append(list(e))
    reps = sum(1 for a, b in zip(joined, joined[1:]) if a[0] > 0 and b[0] < 0)
    return reps, joined


def pass_a(acc):
    runs = quiet_runs(acc)
    reps, _ = count_reps(filtfilt(zupt_velocity(acc, runs)))
    return reps


def bias_curve(acc):
    """Residual bias at every sample: measured in each long rest, interpolated."""
    runs = quiet_runs(acc, LONG_REST_MEAN_MS2, LONG_REST_MIN_S)
    if not runs:
        return np.zeros(len(acc))
    centres = np.array([(s + e) / 2 for s, e in runs])
    means = np.array([acc[s:e + 1].mean() for s, e in runs])
    return np.interp(np.arange(len(acc)), centres, means)


def pass_b(acc):
    import stack_sim
    corrected = acc - bias_curve(acc)
    # stack_sim.count captures its reference from the first second, which is
    # already zero here: the buffer holds acceleration with the bias removed.
    return stack_sim.count(1.0 + corrected / G)


def analyze(acc_ms2):
    """acc_ms2: vertical acceleration of the set, m/s², bias removed at rest."""
    acc = np.asarray(acc_ms2, dtype=float)
    return max(pass_a(acc), pass_b(acc))


def from_sim(acc_g):
    """stack_sim produces raw readings in g; the firmware stores them like this."""
    ref = np.mean(acc_g[: int(FS)])
    return (acc_g - ref) * G


if __name__ == "__main__":
    import stack_sim as sim

    rng = np.random.default_rng(3)
    try:
        from scipy.signal import sosfilt as scipy_sosfilt
        x = rng.normal(0, 1, 2000)
        sos = np.array([[*s[:3], 1.0, *s[3:]] for s in SOS])
        ref = scipy_sosfilt(sos, scipy_sosfilt(sos, x)[::-1])[::-1]
        print(f"filtro igual a scipy: error máximo {np.max(np.abs(filtfilt(x) - ref)):.2e}")
    except ImportError:
        pass

    # What the user ends up with: the live count, plus what the analysis adds
    # when it finds more (it never takes reps away).
    tally = {"series": 0, "vivo de menos": 0, "final de menos": 0, "final de más": 0, "sumó": 0}

    def run(make, n):
        live, final = [], []
        for _ in range(8):
            acc = make()
            l = sim.count(acc)
            f = max(l, analyze(from_sim(acc)))
            live.append(l)
            final.append(f)
            tally["series"] += 1
            tally["vivo de menos"] += l < n
            tally["final de menos"] += f < n
            tally["final de más"] += f > n
            tally["sumó"] += f > l
        bad = "" if min(final) == max(final) == n else "   ✗"
        return f"{n} → en vivo {min(live)}–{max(live)}, con análisis {min(final)}–{max(final)}{bad}"

    for residual in (0.0, 0.0005, -0.0005, 0.001, -0.001, 0.003, -0.003):
        print(f"sesgo residual {residual * 1000:+.1f} mg")
        for name, (n, kw) in sim.CASES.items():
            print(f"  {name}: " + run(lambda: sim.degrading_set(rng, n=n, residual_g=residual, **kw), n))
        for vmax in (0.5, 0.8):
            print(f"  velocidad constante {vmax} m/s: "
                  + run(lambda: sim.constant_velocity_set(rng, vmax=vmax, residual_g=residual), 8))
    quiet = 1.04 + rng.normal(0, 0.00106, int(20 * FS))
    print("quieto 20 s → análisis", analyze(from_sim(quiet)))
    print("reacomodar el agarre → análisis", analyze(from_sim(sim.fidgeting(rng))))
    print(", ".join(f"{k}: {v}" for k, v in tally.items()))
