"""
Takes apart a developer-mode capture (Documents/captures/*.json in the app)
and says how many reps there were, from the raw accelerometer, next to what
the board counted and what the user says they did.

    python3 analyze_capture.py captures/*.json          # table + one PNG each
    python3 analyze_capture.py --no-plots captures/*.json

How the reps are found offline (no live constraints, the whole set at once):
the vertical acceleration (|a| − 1 g, which does not care how the sensor is
turned) is band-passed to 0.15–3 Hz with an FFT and integrated twice in the
frequency domain, which gives the displacement without drift. Each clear
peak of that curve is a rep (prominence at least 35 % of the typical one).
The dominant period comes from the autocorrelation of the same signal.

It also runs the firmware's counter (stack_sim.count, the Python reference
of set_analysis.h) over the raw readings, with the magnitude and with the
old projection, at sensitivity 0, 50 and 100: if that disagrees with what the
board counted live, the board is not running the code we think.
"""

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import stack_sim  # noqa: E402

FS = 104.0
GAP = -32768


def load(path):
    c = json.loads(Path(path).read_text())
    raw = np.array(c.get("raw", []), dtype=float).reshape(-1, 3) if c.get("raw") else np.zeros((0, 3))
    lost = raw[:, 0] == GAP if len(raw) else np.zeros(0, bool)
    if lost.any() and (~lost).any():
        idx = np.arange(len(raw))
        for k in range(3):
            raw[lost, k] = np.interp(idx[lost], idx[~lost], raw[~lost, k])
    c["_acc"] = raw * c.get("rawGPerCount", 0.122e-3)          # g, sensor frame
    c["_lost"] = lost
    c["_t"] = c.get("rawStart", 0.0) + np.arange(len(raw)) / FS
    st = np.array(c.get("states", []), dtype=float)
    c["_states"] = st if st.ndim == 2 and len(st) else np.zeros((0, 5))
    return c


def band(x, lo=0.15, hi=3.0):
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / FS)
    X = np.fft.rfft(x - x.mean())
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, n), X, f


def displacement(acc_g):
    """Band-limited double integral of the vertical acceleration, in cm."""
    n = len(acc_g)
    f = np.fft.rfftfreq(n, 1 / FS)
    X = np.fft.rfft((acc_g - acc_g.mean()) * stack_sim.G)
    keep = (f >= 0.15) & (f <= 3.0)
    D = np.zeros_like(X)
    D[keep] = -X[keep] / (2 * np.pi * f[keep]) ** 2
    return np.fft.irfft(D, n) * 100


def peaks(y, min_sep_s=0.5):
    """Local maxima with their prominence; keeps the clear ones."""
    sep = int(min_sep_s * FS)
    cand = [i for i in range(1, len(y) - 1) if y[i] >= y[i - 1] and y[i] > y[i + 1]]
    found = []
    for i in cand:
        lo = max(0, i - 3 * sep)
        hi = min(len(y), i + 3 * sep)
        left = y[lo:i].min() if i > lo else y[i]
        right = y[i + 1:hi].min() if hi > i + 1 else y[i]
        found.append((i, y[i] - max(left, right)))
    if not found:
        return []
    proms = np.array([p for _, p in found])
    typical = np.median(np.sort(proms)[-max(1, len(proms) // 3):])
    keep = [(i, p) for i, p in found if p >= 0.35 * typical and p >= 1.0]
    out = []
    for i, p in keep:                      # one per min_sep window, the tallest
        if out and i - out[-1][0] < sep:
            if p > out[-1][1]:
                out[-1] = (i, p)
        else:
            out.append((i, p))
    return out


def dominant_period(x):
    x = x - x.mean()
    if len(x) < FS * 3 or not x.any():
        return None
    ac = np.correlate(x, x, "full")[len(x) - 1:]
    ac /= ac[0]
    lo, hi = int(0.5 * FS), min(len(ac) - 1, int(10 * FS))
    if hi <= lo:
        return None
    k = lo + int(np.argmax(ac[lo:hi]))
    return k / FS if ac[k] > 0.2 else None


def analyze(c):
    acc = c["_acc"]
    out = {"file": c.get("id"), "exercise": c.get("exerciseName"), "profile": c.get("firmwareProfile"),
           "board": c.get("liveReps"), "analysis": c.get("analysisFound"),
           "recorded": c.get("recordedReps"), "true": c.get("trueReps"),
           "lost": c.get("rawLostPackets", 0), "samples": len(acc)}
    if len(acc) < FS * 2:
        return out
    mag = np.linalg.norm(acc, axis=1)
    ref = acc[: int(FS)].mean(0)
    proj = acc @ ref / np.linalg.norm(ref)
    disp = displacement(mag)
    pk = peaks(disp)
    out.update({
        "offline": len(pk),
        "period": dominant_period(band(mag)[0]),
        "amp_cm": float(np.median([p for _, p in pk])) if pk else None,
        "tilt_deg": float(np.degrees(np.max(np.arccos(np.clip(
            (acc @ ref) / (np.linalg.norm(acc, axis=1) * np.linalg.norm(ref) + 1e-9), -1, 1))))),
        "sim_mag": {s: stack_sim.count(mag, s) for s in (0, 50, 100)},
        "sim_proj": stack_sim.count(proj, 50),
    })
    out["_mag"], out["_proj"], out["_disp"], out["_peaks"] = mag, proj, disp, pk
    return out


def plot(c, r, png):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    t = c["_t"]
    st = c["_states"]
    reps = [e[0] for e in c.get("events", []) if e[1] == "rep"]
    fig, ax = plt.subplots(5, 1, figsize=(13, 13), sharex=True)
    title = (f"{c.get('exerciseName')} · serie {c.get('setNumber')} · placa {r['board']} · "
             f"offline {r.get('offline')} · real {r['true']}")
    fig.suptitle(title)
    if len(t):
        for k, name in enumerate("xyz"):
            ax[0].plot(t, c["_acc"][:, k], lw=0.7, label=name)
        ax[0].set_ylabel("g (ejes del sensor)")
        ax[0].legend(loc="upper right")
        ax[1].plot(t, (r["_mag"] - r["_mag"][:104].mean()) * 1000, lw=0.7, label="|a| (magnitud)")
        ax[1].plot(t, (r["_proj"] - r["_proj"][:104].mean()) * 1000, lw=0.7, alpha=0.7, label="proyección")
        ax[1].set_ylabel("vertical, mg")
        ax[1].legend(loc="upper right")
        ax[3].plot(t, r["_disp"], lw=1)
        for i, _ in r["_peaks"]:
            ax[3].axvline(t[i], color="tab:green", lw=1)
        ax[3].set_ylabel("desplazamiento\noffline, cm")
    if len(st):
        ax[2].plot(st[:, 0], st[:, 2], lw=0.8, label="valor de la placa")
        h = np.concatenate([[0], np.cumsum((st[1:, 2] + st[:-1, 2]) / 2 * np.diff(st[:, 0]))])
        ax2 = ax[2].twinx()
        ax2.plot(st[:, 0], h, color="tab:orange", lw=0.8, label="su integral")
        ax[2].set_ylabel("cm/s o °")
        ax2.set_ylabel("cm")
        ax[4].step(st[:, 0], st[:, 1], where="post")
    ax[4].set_ylabel("conteo placa")
    for a in ax:
        for tr in reps:
            a.axvline(tr, color="tab:red", lw=0.6, alpha=0.5)
    ax[-1].set_xlabel("s")
    fig.tight_layout()
    fig.savefig(png, dpi=80)
    plt.close(fig)


def main(argv):
    plots = "--no-plots" not in argv
    files = [a for a in argv if not a.startswith("--")]
    rows = []
    for f in files:
        c = load(f)
        r = analyze(c)
        rows.append(r)
        if plots and r.get("samples"):
            plot(c, r, Path(f).with_suffix(".png"))
    print(f"{'captura':42} {'perf':>4} {'real':>4} {'placa':>5} {'anál':>4} {'offl':>4} "
          f"{'sim0/50/100':>11} {'proy':>4} {'per s':>5} {'amp':>5} {'giro°':>5} {'perd':>4}")
    for r in rows:
        s = r.get("sim_mag") or {}
        fmt = lambda v, w, d=0: (f"{v:{w}.{d}f}" if isinstance(v, float) else f"{'—' if v is None else v:>{w}}")
        print(f"{str(r['file'])[:42]:42} {fmt(r['profile'],4)} {fmt(r['true'],4)} {fmt(r['board'],5)} "
              f"{fmt(r['analysis'],4)} {fmt(r.get('offline'),4)} "
              f"{'/'.join(str(s.get(k, '—')) for k in (0, 50, 100)):>11} {fmt(r.get('sim_proj'),4)} "
              f"{fmt(r.get('period'),5,2)} {fmt(r.get('amp_cm'),5,1)} {fmt(r.get('tilt_deg'),5,0)} "
              f"{fmt(r['lost'],4)}")


if __name__ == "__main__":
    main(sys.argv[1:])
