/*
 * Weight-stack counting (firmware profile 2): the live counter, the recording
 * of the set, and the end-of-set analysis.
 *
 * Plain C++ with no Arduino dependencies, so the same code runs on the board
 * and in the host test (test/set_analysis_test.cpp), which checks it against
 * the Python reference in set_analysis.py.
 *
 * Live (StackCounter): sample by sample, velocity from the vertical
 * acceleration, ZUPT when the stack is still, and a rep for every stroke up
 * and back down of at least 4 cm, told apart by the sign of the velocity.
 * The app can raise that minimum (minRomForGrip) when taking the handle
 * lifts the stack further than that.
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

static const float DEADBAND_MPS = 0.02f;   // slower than this is not moving
static const float MIN_ROM_M = 0.04f;      // travel each way to be a stroke
static const float GRIP_MARGIN_M = 0.02f;  // above the grip lift, to be a stroke
static const uint8_t MAX_GRIP_LIFT_CM = 30;
static const float LEAK_TAU_S = 3.0f;      // residual error fades instead of piling up
static const float DEADBAND_G = 0.005f;    // sensor noise, not movement
static const float STILL_ALPHA = 0.1f;     // rest is judged on a smoothed signal...
static const float STILL_G = 0.006f;       // ...below this...
static const uint32_t STILL_MS = 250;      // ...for this long
static const uint32_t IDLE_MS = 3000;      // a lift that never came down
static const uint32_t REFRACTORY_MS = 600;

/* Travel each way to be a stroke, given how far the stack rises when the
   user takes the handle (set from the app, per exercise). Taking it, letting
   go and settling the grip move the stack by about that much, so a stroke
   has to go clearly past it. */
inline float minRomForGrip(uint8_t gripLiftCm) {
  if (gripLiftCm > MAX_GRIP_LIFT_CM) gripLiftCm = MAX_GRIP_LIFT_CM;
  float rom = gripLiftCm * 0.01f + GRIP_MARGIN_M;
  return rom > MIN_ROM_M ? rom : MIN_ROM_M;
}

struct StackCounter {
  enum Phase : uint8_t { IDLE, LIFTING, LOWERING };

  float velocity = 0.0f;       // m/s, positive up
  float smoothed = 0.0f;
  float rise = 0.0f;           // m travelled up in the current stroke
  float fall = 0.0f;           // m travelled down
  Phase phase = IDLE;
  uint32_t stillSinceMs = 0;
  uint32_t lastRepMs = 0;
  bool anyRep = false;
  uint16_t reps = 0;
  float minRom = MIN_ROM_M;    // setting, survives reset()

  void reset() {
    float keep = minRom;
    *this = StackCounter();
    minRom = keep;
  }

  /* vertical: acceleration along the vertical in g, with the rest reading
     already subtracted. Returns true when this sample completed a rep. */
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

    const float v = velocity;
    switch (phase) {
      case IDLE:
        // Travel up adds; any real move down, or a stop, starts over. The
        // bump of the stack landing is a few millimetres and never reaches
        // the minimum. Nor does taking the handle: it lifts the stack a few
        // centimetres and holds it there, which is not the start of a rep.
        if (v > DEADBAND_MPS) rise += v * DT;
        else if (v < -DEADBAND_MPS || still) rise = 0.0f;
        if (rise >= minRom) {
          phase = LIFTING;
          fall = 0.0f;
        }
        break;
      case LIFTING:
        if (v < -DEADBAND_MPS) fall += -v * DT;
        else if (v > DEADBAND_MPS) fall = 0.0f;
        if (fall >= minRom) {
          phase = LOWERING;
        } else if (still && nowMs - stillSinceMs >= IDLE_MS) {
          phase = IDLE;
          rise = 0.0f;
        }
        break;
      case LOWERING:
        if (v > -DEADBAND_MPS) {   // the descent ended
          phase = IDLE;
          rise = 0.0f;
          if (!anyRep || nowMs - lastRepMs >= REFRACTORY_MS) {
            reps++;
            lastRepMs = nowMs;
            anyRep = true;
            return true;
          }
        }
        break;
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
                      float minRom = MIN_ROM_M) {
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
  counter.minRom = minRom;
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
                      float minRom = MIN_ROM_M) {
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

  // Drop the small ones (grip adjustments), join same-sign neighbours, and
  // count every up followed by a down.
  uint16_t reps = 0;
  int8_t previous = 0;
  for (uint16_t k = 0; k < count; k++) {
    if (w.excursions[k].travel < minRom) continue;
    int8_t sign = w.excursions[k].sign;
    if (sign == previous) continue;        // joined with the one before
    if (previous > 0 && sign < 0) reps++;
    previous = sign;
  }
  return reps;
}

/* Runs both passes over the recording and returns the larger count.
   Destroys the recording (pass A works in place). */
inline uint16_t analyzeSet(int16_t *samples, uint32_t n, Workspace &w,
                           float minRom = MIN_ROM_M) {
  if (n < 2) return 0;
  uint16_t b = passB(samples, n, w, minRom);
  uint16_t a = passA(samples, n, w, minRom);
  return a > b ? a : b;
}

}  // namespace stack

#endif
