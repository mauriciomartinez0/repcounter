/*
 * Weight-stack counting (firmware profile 2): the live counter, the recording
 * of the set, and the end-of-set analysis.
 *
 * Plain C++ with no Arduino dependencies, so the same code runs on the board
 * and in the host test (test/set_analysis_test.cpp), which checks it against
 * the Python reference in set_analysis.py.
 *
 * Live (StackCounter): sample by sample, velocity from the vertical
 * acceleration, ZUPT when the stack is still, height from the velocity, and
 * one wave per trough -> peak -> trough of the height. The waves that repeat
 * (similar period, not much smaller than the others) are reps (Periodic):
 * taking the handle or settling the grip makes a wave too, but not one like
 * the reps, so there is nothing to configure.
 *
 * End of set (analyzeSet): two passes over the recording; the set gets the
 * larger count. The app compares it with the live count and only ever offers
 * to ADD the difference, which the user confirms.
 *   A. TRASPASO.md: rest windows, residual bias, velocity with ZUPT anchored
 *      on the edges of each rest window, zero-phase Butterworth, excursions of
 *      the velocity sign.
 *   B. StackCounter again over the recording, with the residual bias measured
 *      in every long rest and interpolated in time.
 */

#ifndef SET_ANALYSIS_H
#define SET_ANALYSIS_H

#include <math.h>
#include <stdint.h>
#include <string.h>

namespace stack {

static const float FS = 104.0f;                 // accelerometer rate
static const float DT = 1.0f / FS;
static const float GRAVITY = 9.80665f;

// ---------------------------------------------------------------------------
// Live counter
// ---------------------------------------------------------------------------

static const float LEAK_TAU_S = 3.0f;      // residual error fades instead of piling up
static const float DEADBAND_G = 0.005f;    // sensor noise, not movement
static const float STILL_ALPHA = 0.1f;     // rest is judged on a smoothed signal...
static const float STILL_G = 0.006f;       // ...below this...
static const uint32_t STILL_MS = 250;      // ...for this long

// Counting by the period of the height curve (stack_sim.py has the same).
// Each threshold goes from strict (sensitivity 0) through the default (50)
// to lenient (100); the app sets the sensitivity live with a slider.
struct Tuning {
  float turnM;           // the height has to come back this much to be a turn
  float minAmpM;         // smaller waves are noise, nudges, the landing bump
  float similarAmp;      // first two reps: amplitude ratio...
  float similarPeriod;   // ...and period ratio
  float ampFraction;     // then: this much of the usual amplitude, or
  float fadeFraction;    // this much of the last rep (a set to failure shrinks)...
  float periodMin;       // ...and a period within this of the usual one
  float periodMax;
  float settled;         // resting counts as the bottom only this far down
};

//                                 turn   minAmp  simA  simP  ampF  fadeF  perMin      perMax settled
static const Tuning TUNING_STRICT  = { 0.03f, 0.05f,  0.5f, 0.6f, 0.5f, 0.8f,  0.5f,       2.0f, 0.8f };
static const Tuning TUNING_DEFAULT = { 0.02f, 0.03f, 0.35f, 0.5f, 0.3f, 0.6f,  1.0f / 3,   3.0f, 0.5f };
static const Tuning TUNING_LENIENT = { 0.01f, 0.015f, 0.2f, 0.35f, 0.15f, 0.3f, 0.3f,      5.0f, 0.25f };
static const uint8_t DEFAULT_SENSITIVITY = 50;

/* The thresholds for a sensitivity of 0–100. 50 gives the defaults exactly. */
inline Tuning tuningFor(uint8_t sensitivity) {
  if (sensitivity > 100) sensitivity = 100;
  const Tuning &m = TUNING_DEFAULT;
  const Tuning &e = sensitivity < 50 ? TUNING_STRICT : TUNING_LENIENT;
  float f = sensitivity < 50 ? (50 - sensitivity) / 50.0f : (sensitivity - 50) / 50.0f;
  auto mix = [f](float mid, float end) { return mid + (end - mid) * f; };
  return { mix(m.turnM, e.turnM), mix(m.minAmpM, e.minAmpM), mix(m.similarAmp, e.similarAmp),
           mix(m.similarPeriod, e.similarPeriod), mix(m.ampFraction, e.ampFraction),
           mix(m.fadeFraction, e.fadeFraction), mix(m.periodMin, e.periodMin),
           mix(m.periodMax, e.periodMax), mix(m.settled, e.settled) };
}

static const float NEAR_M = 0.01f;         // still at the bottom: the rep has not left yet
static const uint32_t SETTLE_MS = 800;     // resting this long closes a wave: a slow stroke reads as rest midway
static const uint8_t HISTORY = 5;
static const uint8_t PENDING = 3;          // waves kept while waiting for the first pair

// Pass A drops velocity excursions shorter than this before pairing them.
static const float MIN_ROM_M = 0.04f;

/* Which waves are reps: the ones that repeat. The first one waits for a
   second one like it, among the last few waves (then both count); after that a wave counts when its
   period is close to the usual one and it is not much smaller. Taking the
   handle, letting go or settling the grip make waves too, but not like the
   reps of the set. Used live and by pass A. */
struct Periodic {
  float amps[HISTORY];
  float periods[HISTORY];
  uint8_t count = 0;
  float pendingAmp[PENDING];
  float pendingPeriod[PENDING];
  uint8_t pendingCount = 0;
  uint16_t reps = 0;

  static float ratio(float a, float b) {
    float lo = a < b ? a : b, hi = a < b ? b : a;
    return hi > 0.0f ? lo / hi : 0.0f;
  }

  /* Upper median, like sorted(x)[len // 2]. */
  static float median(const float *x, uint8_t n) {
    float s[HISTORY];
    for (uint8_t i = 0; i < n; i++) {
      float v = x[i];
      uint8_t j = i;
      while (j > 0 && s[j - 1] > v) { s[j] = s[j - 1]; j--; }
      s[j] = v;
    }
    return s[n / 2];
  }

  void push(float amp, float period) {
    if (count == HISTORY) {
      for (uint8_t i = 1; i < HISTORY; i++) { amps[i - 1] = amps[i]; periods[i - 1] = periods[i]; }
      count--;
    }
    amps[count] = amp;
    periods[count] = period;
    count++;
  }

  /* amp in m, period in s. Returns how many reps this wave added. */
  uint8_t add(float amp, float period, const Tuning &t) {
    if (amp < t.minAmpM || period <= 0.0f) return 0;
    if (count == 0) {
      for (int8_t i = (int8_t)pendingCount - 1; i >= 0; i--) {   // newest first
        if (ratio(pendingAmp[i], amp) >= t.similarAmp &&
            ratio(pendingPeriod[i], period) >= t.similarPeriod) {
          push(pendingAmp[i], pendingPeriod[i]);
          push(amp, period);
          pendingCount = 0;
          reps += 2;
          return 2;
        }
      }
      if (pendingCount == PENDING) {
        for (uint8_t i = 1; i < PENDING; i++) {
          pendingAmp[i - 1] = pendingAmp[i];
          pendingPeriod[i - 1] = pendingPeriod[i];
        }
        pendingCount--;
      }
      pendingAmp[pendingCount] = amp;
      pendingPeriod[pendingCount] = period;
      pendingCount++;
      return 0;
    }
    float refAmp = median(amps, count), refPeriod = median(periods, count);
    if ((amp >= t.ampFraction * refAmp || amp >= t.fadeFraction * amps[count - 1]) &&
        period >= t.periodMin * refPeriod && period <= t.periodMax * refPeriod) {
      push(amp, period);
      reps++;
      return 1;
    }
    return 0;
  }
};

/* Live counter: velocity from the vertical acceleration (ZUPT when the
   stack is still), height from the velocity, and one wave per trough → peak
   → trough of the height. Periodic decides which waves are reps; there is no
   minimum travel to configure. */
struct StackCounter {
  float velocity = 0.0f;       // m/s, positive up
  float smoothed = 0.0f;
  float height = 0.0f;         // m, from where the set started; drifts, only shape matters
  uint32_t stillSinceMs = 0;
  bool rising = true;
  float trough = 0.0f, peak = 0.0f, bottom = 0.0f;
  uint32_t departMs = 0, arriveMs = 0;
  Periodic waves;
  uint16_t reps = 0;
  Tuning tuning = TUNING_DEFAULT;   // setting, survives reset()

  void reset() {
    Tuning keep = tuning;
    *this = StackCounter();
    tuning = keep;
  }

  /* Going up, for the app's arrow. */
  bool lifting() const { return rising && height > trough + tuning.turnM; }

  /* vertical: acceleration along the vertical in g, with the rest reading
     already subtracted. Returns true when this sample added reps (two at
     once when the second rep confirms the first). */
  bool update(float vertical, uint32_t nowMs) {
    smoothed += STILL_ALPHA * (vertical - smoothed);
    if (fabsf(vertical) < DEADBAND_G) vertical = 0.0f;

    velocity += vertical * GRAVITY * DT;
    velocity -= velocity * (DT / LEAK_TAU_S);

    // Zero-velocity update: a still stack is not moving, whatever the
    // integral says.
    bool still = false;
    if (fabsf(smoothed) < STILL_G) {
      if (stillSinceMs == 0) stillSinceMs = nowMs;
      if (nowMs - stillSinceMs >= STILL_MS) {
        velocity = 0.0f;
        still = true;
      }
    } else {
      stillSinceMs = 0;
    }
    height += velocity * DT;

    const float h = height;
    if (rising) {
      if (h < trough) trough = h;
      if (h <= trough + NEAR_M) { departMs = nowMs; peak = h; }
      if (h > peak) peak = h;
      if (h <= peak - tuning.turnM) {         // turned at the top
        rising = false;
        bottom = h;
        arriveMs = nowMs;
      }
      return false;
    }
    if (h < bottom) { bottom = h; arriveMs = nowMs; }
    // Turned at the bottom, or came to rest there: a full wave. A rest
    // higher up is a pause at the top, not the end of it.
    bool settled = still && nowMs - stillSinceMs >= SETTLE_MS &&
                   peak - bottom >= tuning.settled * (peak - trough);
    if (h >= bottom + tuning.turnM || settled) {
      uint8_t added = waves.add((2.0f * peak - trough - bottom) / 2.0f,
                                (arriveMs - departMs) / 1000.0f, tuning);
      rising = true;
      trough = bottom;
      peak = h;
      departMs = nowMs;
      if (added) {
        reps = waves.reps;
        return true;
      }
    }
    return false;
  }
};

/* Tilt profiles (sensor on the arm, the body or a bar): the same waves, on
   the angle from the calibration pose instead of the height. A wave closes
   when the angle turns up again, or when it stays put near the bottom for
   SETTLE_MS after coming at least `settled` of the way down: the arm does not
   have to get back to the pose it calibrated in. Thresholds in degrees,
   from the same sensitivity as the stack's (count_tilt in stack_sim.py). */
static const float TILT_TURN_DEG_PER_M = 450.0f;   // 2 cm -> 9°
static const float TILT_AMP_DEG_PER_M = 500.0f;    // 3 cm -> 15°

inline Tuning tiltTuningFor(uint8_t sensitivity) {
  Tuning t = tuningFor(sensitivity);
  t.turnM *= TILT_TURN_DEG_PER_M;     // degrees here
  t.minAmpM *= TILT_AMP_DEG_PER_M;
  return t;
}

struct TiltCounter {
  bool rising = true;
  bool started = false;
  float trough = 0.0f, peak = 0.0f, bottom = 0.0f;
  uint32_t departMs = 0, arriveMs = 0, flatSinceMs = 0;
  Periodic waves;
  uint16_t reps = 0;
  Tuning tuning = tiltTuningFor(DEFAULT_SENSITIVITY);   // setting, survives reset()

  void reset() {
    Tuning keep = tuning;
    *this = TiltCounter();
    tuning = keep;
  }

  bool lifting() const { return started && rising && peak > trough + tuning.turnM / 2; }

  /* angle: degrees from the calibration pose. Returns true when this sample
     added reps. */
  bool update(float angle, uint32_t nowMs) {
    const float h = angle;
    if (!started) {
      started = true;
      trough = peak = bottom = h;
      departMs = arriveMs = flatSinceMs = nowMs;
    }
    if (rising) {
      if (h < trough) trough = h;
      if (h <= trough + tuning.turnM / 2) { departMs = nowMs; peak = h; }
      if (h > peak) peak = h;
      if (h <= peak - tuning.turnM) {
        rising = false;
        bottom = h;
        arriveMs = flatSinceMs = nowMs;
      }
      return false;
    }
    if (h < bottom) { bottom = h; arriveMs = nowMs; }
    if (h > bottom + tuning.turnM / 2 || h < bottom - tuning.turnM / 2) flatSinceMs = nowMs;
    bool settled = nowMs - flatSinceMs >= SETTLE_MS &&
                   peak - bottom >= tuning.settled * (peak - trough);
    if (h >= bottom + tuning.turnM || settled) {
      uint8_t added = waves.add((2.0f * peak - trough - bottom) / 2.0f,
                                (arriveMs - departMs) / 1000.0f, tuning);
      rising = true;
      trough = bottom;
      peak = h;
      departMs = nowMs;
      if (added) {
        reps = waves.reps;
        return true;
      }
    }
    return false;
  }
};

// ---------------------------------------------------------------------------
// Recording
// ---------------------------------------------------------------------------

// Vertical acceleration in mm/s², 16 bits: ±32 m/s², 0.1 mg resolution.
// 120 s at 104 Hz is 25 KB of RAM.
static const uint32_t RECORD_CAPACITY = 12480;

struct SetRecorder {
  int16_t samples[RECORD_CAPACITY];
  uint32_t length = 0;
  bool recording = false;
  bool truncated = false;

  void start() {
    length = 0;
    truncated = false;
    recording = true;
  }

  void stop() { recording = false; }

  /* vertical: acceleration along the vertical in g, rest reading removed. */
  void push(float vertical) {
    if (!recording) return;
    if (length >= RECORD_CAPACITY) {
      truncated = true;
      return;
    }
    float mms2 = vertical * GRAVITY * 1000.0f;
    if (mms2 > 32767.0f) mms2 = 32767.0f;
    if (mms2 < -32767.0f) mms2 = -32767.0f;
    samples[length++] = (int16_t)lroundf(mms2);
  }
};

// ---------------------------------------------------------------------------
// End-of-set analysis
// ---------------------------------------------------------------------------

// TRASPASO.md section 8, plus a mean test on the rest detector (see
// set_analysis.py for why). All of them still need real sets to confirm.
static const uint32_t QUIET_HALF_WINDOW = 10;    // 0.2 s centred window
static const int32_t QUIET_STD_MMS2 = 150;       // 0.15 m/s²
static const int32_t QUIET_MEAN_MMS2 = 20;       // pass A
static const uint32_t QUIET_MIN_LEN = 41;        // 0.40 s
static const int32_t LONG_REST_MEAN_MMS2 = 50;   // pass B: rests that measure the bias
static const uint32_t LONG_REST_MIN_LEN = 104;   // 1.0 s
static const float DEADBAND_FRAC = 0.05f;
static const uint32_t MERGE_GAP = 31;            // 0.30 s
static const float VELOCITY_UNIT = 1.0e-4f;      // pass A stores velocity in 0.1 mm/s

// butter(4, 2.0, fs=104.0, output="sos"): b0 b1 b2 a1 a2 per section.
static const float SOS[2][5] = {
  { 1.1431134452625980e-05f, 2.2862268905251960e-05f, 1.1431134452625980e-05f,
    -1.7864735976669488e+00f, 7.9959466897088638e-01f },
  { 1.0f, 2.0f, 1.0f, -1.8978737830369070e+00f, 9.1181305270516411e-01f },
};

struct Run { uint16_t start, end; };            // inclusive
struct Excursion { int8_t sign; uint16_t start, end; float travel; };

static const uint16_t MAX_RUNS = 256;
static const uint16_t MAX_EXCURSIONS = 512;
static const uint16_t HISTOGRAM_BINS = 2048;     // |v| in 1.6 mm/s steps

struct Workspace {
  Run runs[MAX_RUNS];
  float centre[MAX_RUNS];                        // pass B: long rests
  float bias[MAX_RUNS];
  Excursion excursions[MAX_EXCURSIONS];
  uint16_t histogram[HISTOGRAM_BINS];
};

/* Stretches at rest: rolling standard deviation AND mean below the limits,
   over a centred window, for at least minLen samples. Exact integer sums. */
inline uint16_t findQuietRuns(const int16_t *a, uint32_t n, int32_t meanLimit,
                              uint32_t minLen, Run *runs, uint16_t maxRuns) {
  uint16_t count = 0;
  int64_t sum = 0, sumSq = 0;
  uint32_t lo = 0, hi = 0;          // window [lo, hi)
  uint32_t runStart = 0;
  bool inRun = false;
  for (uint32_t i = 0; i <= n; i++) {
    bool quiet = false;
    if (i < n) {
      uint32_t wantLo = i > QUIET_HALF_WINDOW ? i - QUIET_HALF_WINDOW : 0;
      uint32_t wantHi = i + QUIET_HALF_WINDOW + 1 < n ? i + QUIET_HALF_WINDOW + 1 : n;
      while (hi < wantHi) { sum += a[hi]; sumSq += (int64_t)a[hi] * a[hi]; hi++; }
      while (lo < wantLo) { sum -= a[lo]; sumSq -= (int64_t)a[lo] * a[lo]; lo++; }
      int64_t m = hi - lo;
      // var < std² and |mean| < limit, scaled by m² and m to stay in integers.
      int64_t varM2 = sumSq * m - sum * sum;
      quiet = varM2 < (int64_t)QUIET_STD_MMS2 * QUIET_STD_MMS2 * m * m &&
              (sum < 0 ? -sum : sum) < (int64_t)meanLimit * m;
    }
    if (quiet && !inRun) { inRun = true; runStart = i; }
    if (!quiet && inRun) {
      inRun = false;
      if (i - runStart >= minLen && count < maxRuns) {
        runs[count].start = (uint16_t)runStart;
        runs[count].end = (uint16_t)(i - 1);
        count++;
      }
    }
  }
  return count;
}

/* Pass B: the live counter over the recording, residual bias corrected. */
inline uint16_t passB(const int16_t *a, uint32_t n, Workspace &w,
                      const Tuning &tuning = TUNING_DEFAULT) {
  uint16_t runCount = findQuietRuns(a, n, LONG_REST_MEAN_MMS2, LONG_REST_MIN_LEN, w.runs, MAX_RUNS);
  // Bias of each long rest, at its centre; interpolated between centres.
  float *centre = w.centre, *bias = w.bias;
  for (uint16_t r = 0; r < runCount; r++) {
    int64_t s = 0;
    for (uint32_t i = w.runs[r].start; i <= w.runs[r].end; i++) s += a[i];
    centre[r] = 0.5f * (w.runs[r].start + w.runs[r].end);
    bias[r] = (float)s / (w.runs[r].end - w.runs[r].start + 1);
  }
  uint16_t segment = 1;                          // samples arrive in order
  auto biasAt = [&](uint32_t i) -> float {
    if (runCount == 0) return 0.0f;
    if (i <= centre[0]) return bias[0];
    if (i >= centre[runCount - 1]) return bias[runCount - 1];
    if (segment < 1 || centre[segment - 1] > i) segment = 1;
    while (centre[segment] < i) segment++;
    float t = (i - centre[segment - 1]) / (centre[segment] - centre[segment - 1]);
    return bias[segment - 1] + t * (bias[segment] - bias[segment - 1]);
  };
  // Like the live counter, start from a rest reference: the first second.
  uint32_t refLen = n < 104 ? n : 104;
  float ref = 0.0f;
  for (uint32_t i = 0; i < refLen; i++) ref += a[i] - biasAt(i);
  ref = refLen ? ref / refLen : 0.0f;

  StackCounter counter;
  counter.tuning = tuning;
  for (uint32_t i = 0; i < n; i++) {
    float vertical = (a[i] - biasAt(i) - ref) / (1000.0f * GRAVITY);
    counter.update(vertical, (uint32_t)(i * 1000.0f / FS));
  }
  return counter.reps;
}

inline int16_t toVelocityUnits(float v) {
  float u = v / VELOCITY_UNIT;
  if (u > 32767.0f) u = 32767.0f;
  if (u < -32767.0f) u = -32767.0f;
  return (int16_t)lroundf(u);
}

/* Pass A: TRASPASO.md. Turns the recording into velocity, in place. */
inline uint16_t passA(int16_t *a, uint32_t n, Workspace &w,
                      const Tuning &tuning = TUNING_DEFAULT) {
  uint16_t runCount = findQuietRuns(a, n, QUIET_MEAN_MMS2, QUIET_MIN_LEN, w.runs, MAX_RUNS);

  // Residual bias: whatever the rest windows still read.
  float bias = 0.0f;
  if (runCount) {
    int64_t s = 0, len = 0;
    for (uint16_t r = 0; r < runCount; r++)
      for (uint32_t i = w.runs[r].start; i <= w.runs[r].end; i++) { s += a[i]; len++; }
    bias = (float)s / len;
  }

  // Integrate to velocity, in place (0.1 mm/s units).
  float v = 0.0f;
  for (uint32_t i = 0; i < n; i++) {
    v += (a[i] - bias) * 1.0e-3f * DT;
    a[i] = toVelocityUnits(v);
  }

  // ZUPT: subtract the line between rest anchors, so velocity is 0 at the
  // start, at both edges of every rest window, and inside it.
  uint32_t prevI = 0;
  float prevV = 0.0f;
  bool first = true;
  for (uint16_t r = 0; r < runCount; r++) {
    uint32_t s = w.runs[r].start, e = w.runs[r].end;
    float vs = a[s] * VELOCITY_UNIT;
    float ve = a[e] * VELOCITY_UNIT;   // read before the run is zeroed
    if (s > prevI) {
      float span = (float)(s - prevI);
      for (uint32_t i = first ? prevI : prevI + 1; i < s; i++) {
        float line = prevV + (vs - prevV) * (i - prevI) / span;
        a[i] = toVelocityUnits(a[i] * VELOCITY_UNIT - line);
      }
    }
    for (uint32_t i = s; i <= e; i++) a[i] = 0;
    prevI = e;
    prevV = ve;
    first = false;
  }
  // After the last anchor there is none ahead: only the offset.
  for (uint32_t i = first ? 0 : prevI + 1; i < n; i++) {
    a[i] = toVelocityUnits(a[i] * VELOCITY_UNIT - prevV);
  }

  // Zero-phase Butterworth: forward, then backward (transposed form II).
  for (int direction = 0; direction < 2; direction++) {
    float z[2][2] = { { 0, 0 }, { 0, 0 } };
    for (uint32_t k = 0; k < n; k++) {
      uint32_t i = direction == 0 ? k : n - 1 - k;
      float x = a[i] * VELOCITY_UNIT;
      for (int s = 0; s < 2; s++) {
        const float *c = SOS[s];
        float y = c[0] * x + z[s][0];
        z[s][0] = c[1] * x - c[3] * y + z[s][1];
        z[s][1] = c[2] * x - c[4] * y;
        x = y;
      }
      a[i] = toVelocityUnits(x);
    }
  }

  // Deadband: 5 % of the 99th percentile of |v|, from a histogram.
  memset(w.histogram, 0, sizeof(w.histogram));
  for (uint32_t i = 0; i < n; i++) {
    uint32_t mag = a[i] < 0 ? -a[i] : a[i];
    uint32_t bin = mag / 16;
    if (bin >= HISTOGRAM_BINS) bin = HISTOGRAM_BINS - 1;
    w.histogram[bin]++;
  }
  uint32_t target = (uint32_t)ceilf(0.99f * n), seen = 0, bin = 0;
  for (; bin < HISTOGRAM_BINS; bin++) {
    seen += w.histogram[bin];
    if (seen >= target) break;
  }
  int32_t deadband = (int32_t)(DEADBAND_FRAC * (bin * 16 + 8));

  // Excursions of the velocity sign, merging same-sign ones that are close.
  uint16_t count = 0;
  for (uint32_t i = 0; i < n;) {
    int8_t sign = a[i] > deadband ? 1 : (a[i] < -deadband ? -1 : 0);
    if (sign == 0) { i++; continue; }
    uint32_t j = i;
    float travel = 0.0f;
    while (j < n && (sign > 0 ? a[j] > deadband : a[j] < -deadband)) {
      travel += (a[j] < 0 ? -a[j] : a[j]) * VELOCITY_UNIT * DT;
      j++;
    }
    Excursion &last = w.excursions[count ? count - 1 : 0];
    if (count && last.sign == sign && i - last.end <= MERGE_GAP) {
      last.end = (uint16_t)(j - 1);
      last.travel += travel;
    } else if (count < MAX_EXCURSIONS) {
      w.excursions[count++] = { sign, (uint16_t)i, (uint16_t)(j - 1), travel };
    }
    i = j;
  }

  // Drop the small ones (nudges, bumps) and join same-sign neighbours, in
  // place. Every up followed by a down is a wave; the ones that repeat are
  // reps, as live.
  uint16_t joined = 0;
  for (uint16_t k = 0; k < count; k++) {
    const Excursion e = w.excursions[k];
    if (e.travel < MIN_ROM_M) continue;
    if (joined && w.excursions[joined - 1].sign == e.sign) {
      w.excursions[joined - 1].end = e.end;
      w.excursions[joined - 1].travel += e.travel;
    } else {
      w.excursions[joined++] = e;
    }
  }
  Periodic waves;
  for (uint16_t k = 0; k + 1 < joined; k++) {
    const Excursion &up = w.excursions[k], &down = w.excursions[k + 1];
    if (up.sign > 0 && down.sign < 0)
      waves.add((up.travel + down.travel) / 2.0f, (down.end - up.start) * DT, tuning);
  }
  return waves.reps;
}

/* Runs both passes over the recording and returns the larger count.
   Destroys the recording (pass A works in place). */
inline uint16_t analyzeSet(int16_t *samples, uint32_t n, Workspace &w,
                           const Tuning &tuning = TUNING_DEFAULT) {
  if (n < 2) return 0;
  uint16_t b = passB(samples, n, w, tuning);
  uint16_t a = passA(samples, n, w, tuning);
  return a > b ? a : b;
}

}  // namespace stack

#endif
