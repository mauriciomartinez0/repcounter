/*
 * XIAO nRF52840 Sense - BLE rep counter
 *
 * Counts repetitions for two exercises and publishes the count over BLE.
 *
 * Why this needs none of the velocity pipeline:
 *   Counting reps does not require integration. Both target exercises rotate
 *   the sensor substantially (upper arm during a push-up, forearm during a
 *   curl), so the direction of gravity relative to the sensor swings through
 *   a wide arc once per rep. Gravity is an absolute reference that never
 *   drifts, so a tilt angle derived from it needs no bias calibration and
 *   accumulates no error, unlike anything built on integrating acceleration.
 *
 * Algorithm:
 *   1. Low-pass the accelerometer to estimate the gravity direction.
 *   2. Capture a reference direction once the device has been still.
 *   3. Track the angle between current gravity and that reference.
 *   4. Count the waves of that angle that repeat (stack::TiltCounter): a
 *      rep is a rise and a fall like the others, with no fixed angle to
 *      reach or to come back under.
 *
 * The gyroscope is powered down: it contributes nothing here and costs power.
 *
 * Weight stack (profile 2): on a cable or selector machine the sensor sits on
 * the top plate of the stack, which moves straight up and down without
 * rotating, so the tilt angle never changes. That profile follows vertical
 * velocity instead: the length of the acceleration minus its length at rest
 * (1 g plus the vertical acceleration, however the sensor is turned, so a
 * tilted or hand-held sensor does not leak gravity in), integrated with a
 * slow leak and reset to zero whenever the stack is still. Integrated again it
 * is the height of the stack, one wave per rep, and the count follows the
 * PERIOD of that curve: the waves that repeat (similar period, not much
 * smaller than the others) are reps. Taking the handle, letting go or
 * settling the grip make waves too, but not like the reps of the set, so
 * nothing has to be configured. The first rep shows up when the second one
 * confirms it. Checked against simulated sets with the measured noise and
 * bias (stack_sim.py); still needs confirming with real ones.
 *
 * Bar that starts at the top (profile 3): bench press, squat, RDL. The bar
 * moves straight up and down without turning, like a stack, so it counts the
 * same way, on the height curve upside down. A stack starts at rest at the
 * bottom and a rep (up, then down) ends when it comes back; a bench press
 * starts with the arms locked out, so a rep is down, then up, and has to end
 * at the top. Counted the right way up, each rep only closed when the next
 * one started down and the last one never did: a set of 8 read 7. Flipping
 * the sign of the vertical acceleration makes the press look like a stack to
 * the counter, so the rep counts as soon as the bar is back up. Bars that
 * start at the bottom (deadlift, overhead press, rows) use profile 2 as is.
 *
 * The board also records the set (vertical acceleration, 120 s at most) and,
 * when the app closes the set (CMD_ANALYZE), analyses it as TRASPASO.md
 * describes and answers on the analysis characteristic. The app offers the
 * reps the live count missed, if any, for the user to confirm. All of it is
 * in set_analysis.h.
 *
 * Battery: the charge level goes out through the standard BLE Battery Service
 * (0x180F / 0x2A19), separate from the rep-counter service, so apps that do not
 * know about it keep working unchanged.
 *
 * Platform facts, verified on this hardware (core 1.1.13):
 *   Bus       : Wire1, SDA = 17, SCL = 16
 *   Address   : 0x6A
 *   Power pin : Arduino 15 = nRF P1.08, needs HIGH DRIVE (S0H1).
 *               A plain digitalWrite browns the sensor out: it holds SDA low
 *               without answering, which stalls the nRF52 TWIM forever.
 *   Interrupt : Arduino 18 = INT1
 *
 * Board: "Seeed XIAO nRF52840 Sense", package "Seeed nRF52 Boards"
 */

#include <bluefruit.h>
#include <Wire.h>

// Weight-stack counting, recording and end-of-set analysis. Plain C++ shared
// with the host test (test/set_analysis_test.cpp).
#include "set_analysis.h"

// ---------------------------------------------------------------------------
// BLE identifiers
// ---------------------------------------------------------------------------

// Custom 128-bit UUIDs, byte-reversed as the Bluefruit API expects.
// Service a1b20001-7f3c-4e8d-9a6b-2c5d8e0f1a3b
const uint8_t UUID_SERVICE[16] = {
  0x3b, 0x1a, 0x0f, 0x8e, 0x5d, 0x2c, 0x6b, 0x9a,
  0x8d, 0x4e, 0x3c, 0x7f, 0x01, 0x00, 0xb2, 0xa1
};
// State   a1b20002-...
const uint8_t UUID_STATE[16] = {
  0x3b, 0x1a, 0x0f, 0x8e, 0x5d, 0x2c, 0x6b, 0x9a,
  0x8d, 0x4e, 0x3c, 0x7f, 0x02, 0x00, 0xb2, 0xa1
};
// Control a1b20003-...
const uint8_t UUID_CONTROL[16] = {
  0x3b, 0x1a, 0x0f, 0x8e, 0x5d, 0x2c, 0x6b, 0x9a,
  0x8d, 0x4e, 0x3c, 0x7f, 0x03, 0x00, 0xb2, 0xa1
};

// Analysis a1b20004-... (notify): result of the end-of-set analysis.
const uint8_t UUID_ANALYSIS[16] = {
  0x3b, 0x1a, 0x0f, 0x8e, 0x5d, 0x2c, 0x6b, 0x9a,
  0x8d, 0x4e, 0x3c, 0x7f, 0x04, 0x00, 0xb2, 0xa1
};

// Raw a1b20005-... (notify): developer mode, the accelerometer as read.
const uint8_t UUID_RAW[16] = {
  0x3b, 0x1a, 0x0f, 0x8e, 0x5d, 0x2c, 0x6b, 0x9a,
  0x8d, 0x4e, 0x3c, 0x7f, 0x05, 0x00, 0xb2, 0xa1
};

BLEService        repService(UUID_SERVICE);
BLECharacteristic stateCharacteristic(UUID_STATE);
BLECharacteristic controlCharacteristic(UUID_CONTROL);
BLECharacteristic analysisCharacteristic(UUID_ANALYSIS);
BLECharacteristic rawCharacteristic(UUID_RAW);
BLEBas            batteryService;   // standard Battery Service, 0x180F

// Control commands from the app
static const uint8_t CMD_SET_EXERCISE = 0x01;   // payload: exercise id
static const uint8_t CMD_RESET_COUNT  = 0x02;
static const uint8_t CMD_REZERO       = 0x03;
static const uint8_t CMD_ANALYZE      = 0x04;   // payload: token echoed back
static const uint8_t CMD_SET_GRIP_LIFT = 0x05;  // ignored: older apps still send it
static const uint8_t CMD_SET_SENSITIVITY = 0x06; // payload: 0 (strict) to 100 (lenient), 50 by default
static const uint8_t CMD_SET_RAW_STREAM = 0x07;  // payload: 1 streams the raw accelerometer, 0 stops

// Raw packet (developer mode), 20 bytes little endian, about 35 a second:
//   0..1   uint16  sequence, +1 per packet: a gap means packets were lost
//   2..19  3 samples of int16 x, y, z in accelerometer counts (0.122 mg),
//          consecutive at 104 Hz, the same readings the counter uses
static const uint8_t RAW_SAMPLES_PER_PACKET = 3;

// Analysis packet, version 1, 8 bytes little endian:
//   0     uint8   version (1)
//   1     uint8   token from CMD_ANALYZE
//   2     uint8   status (below)
//   3..4  uint16  reps found by the analysis
//   5..6  uint16  live count when the set closed
//   7     uint8   reserved
static const uint8_t ANALYSIS_VERSION = 1;
static const uint8_t ANALYSIS_OK = 0;
static const uint8_t ANALYSIS_TRUNCATED = 1;    // the set ran past the buffer
static const uint8_t ANALYSIS_UNAVAILABLE = 2;  // not the stack profile, or nothing recorded

// ---------------------------------------------------------------------------
// IMU
// ---------------------------------------------------------------------------

static const uint8_t IMU_ADDR = 0x6A;

static const uint8_t REG_WHO_AM_I  = 0x0F;
static const uint8_t REG_INT1_CTRL = 0x0D;
static const uint8_t REG_CTRL1_XL  = 0x10;
static const uint8_t REG_CTRL2_G   = 0x11;
static const uint8_t REG_CTRL3_C   = 0x12;
static const uint8_t REG_OUTX_L_XL = 0x28;

static const uint8_t WHO_AM_I_EXPECTED = 0x6A;

// 104 Hz is plenty for counting and leaves headroom. +/-4 g instead of the
// logger's +/-16 g: no barbell drops here, and the finer resolution gives a
// cleaner tilt estimate.
static const uint8_t CFG_CTRL1_XL = 0x48;   // 104 Hz, +/-4 g
static const uint8_t CFG_CTRL2_G  = 0x00;   // gyroscope powered down
static const uint8_t CFG_CTRL3_C  = 0x44;   // BDU + IF_INC
static const uint8_t CFG_INT1     = 0x01;   // INT1 pulses on new accel data
static const uint8_t CTRL3_C_SW_RESET = 0x01;

static const float ACCEL_G_PER_COUNT = 0.122f / 1000.0f;   // +/-4 g range

extern const uint32_t g_ADigitalPinMap[];

// ---------------------------------------------------------------------------
// Exercise profiles
// ---------------------------------------------------------------------------

enum ProfileKind : uint8_t {
  PROFILE_TILT,     // sensor rotates with a limb, the body or a bar
  PROFILE_STACK,    // sensor rides a weight stack straight up and down
};

struct ExerciseProfile {
  const char *name;
  ProfileKind kind;
  // Stack kind only: the movement starts at the top and goes down first
  // (bench press, squat), so the height curve is counted upside down.
  bool fromTop;
};

// Both tilt profiles count the same way, by the period of the angle curve
// (stack::TiltCounter): there are no fixed angles to reach. Before, a rep
// had to pass 25° up and come back under 12° (45° / 20° on the body); with
// the sensor on the arm, a lateral raise that stopped 15–25° short of the
// calibration pose between reps counted 5 of 12.
const ExerciseProfile EXERCISE_PROFILES[] = {
  { "arm",          PROFILE_TILT,  false },   // id 0: sensor on the arm, or a bar that turns (curl)
  { "body",         PROFILE_TILT,  false },   // id 1: sensor on the waist or a backpack
  { "weight stack", PROFILE_STACK, false },   // id 2: sensor on the stack, or a bar that starts low
  { "bar from top", PROFILE_STACK, true  },   // id 3: bar that starts high (bench press, squat)
};
const uint8_t EXERCISE_COUNT = sizeof(EXERCISE_PROFILES) / sizeof(EXERCISE_PROFILES[0]);

uint8_t currentExercise = 0;

// How strict counting is, set live from the app (CMD_SET_SENSITIVITY): it
// moves every threshold of the period counters (stack::tuningFor, and in
// degrees stack::tiltTuningFor).
uint8_t sensitivity = stack::DEFAULT_SENSITIVITY;

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------

float gravityX = 0.0f, gravityY = 0.0f, gravityZ = 1.0f;   // low-passed estimate
bool  filterPrimed = false;

float referenceX = 0.0f, referenceY = 0.0f, referenceZ = 1.0f;
bool  referenceCaptured = false;

uint16_t repCount = 0;
bool     inUpPhase = false;

float currentAngleDeg = 0.0f;

// Stillness detection, used to capture the reference automatically.
float stillnessAccumulator = 0.0f;
uint32_t stillSinceMs = 0;

uint32_t lastNotifyMs = 0;
uint32_t ledOffAtMs = 0;

// Vertical profiles (2 and 3): live counter and recording of the set.
stack::StackCounter stackCounter;
// Tilt profiles (0 and 1).
stack::TiltCounter tiltCounter;

void setSensitivity(uint8_t value) {
  if (value > 100) value = 100;
  sensitivity = value;
  stackCounter.tuning = stack::tuningFor(value);
  tiltCounter.tuning = stack::tiltTuningFor(value);
}

stack::SetRecorder setRecorder;          // 25 KB
stack::Workspace analysisWorkspace;      // about 10 KB, used only at the end

// Commands arrive on the BLE task; the loop applies them, so the counter and
// the recording are only ever touched from one place.
static const uint8_t COMMAND_QUEUE = 8;
volatile uint8_t commandQueue[COMMAND_QUEUE][2];
volatile uint8_t commandHead = 0, commandTail = 0;

// Low-pass coefficient. At 104 Hz this puts the corner near 2 Hz, which keeps
// gravity and rejects the sharp transients of the movement itself.
static const float FILTER_ALPHA = 0.35;

// ---------------------------------------------------------------------------
// IMU helpers
// ---------------------------------------------------------------------------

void powerImuWithHighDrive() {
  uint32_t nrfPin     = g_ADigitalPinMap[PIN_LSM6DS3TR_C_POWER];
  NRF_GPIO_Type *port = (nrfPin < 32) ? NRF_P0 : NRF_P1;
  uint32_t pinIndex   = nrfPin & 0x1F;

  port->PIN_CNF[pinIndex] =
      ((uint32_t)GPIO_PIN_CNF_DIR_Output       << GPIO_PIN_CNF_DIR_Pos)
    | ((uint32_t)GPIO_PIN_CNF_INPUT_Disconnect << GPIO_PIN_CNF_INPUT_Pos)
    | ((uint32_t)GPIO_PIN_CNF_PULL_Disabled    << GPIO_PIN_CNF_PULL_Pos)
    | ((uint32_t)GPIO_PIN_CNF_DRIVE_S0H1       << GPIO_PIN_CNF_DRIVE_Pos)
    | ((uint32_t)GPIO_PIN_CNF_SENSE_Disabled   << GPIO_PIN_CNF_SENSE_Pos);

  port->OUTSET = (1UL << pinIndex);
}

bool writeRegister(uint8_t registerAddress, uint8_t value) {
  Wire1.beginTransmission(IMU_ADDR);
  Wire1.write(registerAddress);
  Wire1.write(value);
  return (Wire1.endTransmission() == 0);
}

bool readRegister(uint8_t registerAddress, uint8_t &valueOut) {
  Wire1.beginTransmission(IMU_ADDR);
  Wire1.write(registerAddress);
  if (Wire1.endTransmission(false) != 0) return false;
  if (Wire1.requestFrom(IMU_ADDR, (uint8_t)1) != 1) return false;
  valueOut = Wire1.read();
  return true;
}

// Developer mode (CMD_SET_RAW_STREAM): the readings go to the app as well.
volatile bool rawStreaming = false;
int16_t lastRaw[3];
int16_t rawBuffer[RAW_SAMPLES_PER_PACKET * 3];
uint8_t rawInPacket = 0;
uint16_t rawSequence = 0;

bool readAccel(float &ax, float &ay, float &az) {
  Wire1.beginTransmission(IMU_ADDR);
  Wire1.write(REG_OUTX_L_XL);
  if (Wire1.endTransmission(false) != 0) return false;
  if (Wire1.requestFrom(IMU_ADDR, (uint8_t)6) != 6) return false;

  uint8_t buffer[6];
  for (uint8_t i = 0; i < 6; i++) buffer[i] = Wire1.read();

  int16_t rawX = (int16_t)((buffer[1] << 8) | buffer[0]);
  int16_t rawY = (int16_t)((buffer[3] << 8) | buffer[2]);
  int16_t rawZ = (int16_t)((buffer[5] << 8) | buffer[4]);

  lastRaw[0] = rawX;
  lastRaw[1] = rawY;
  lastRaw[2] = rawZ;
  ax = rawX * ACCEL_G_PER_COUNT;
  ay = rawY * ACCEL_G_PER_COUNT;
  az = rawZ * ACCEL_G_PER_COUNT;
  return true;
}

/* Developer mode: three readings per notification, numbered so the app can
   tell when some did not arrive (the radio drops them rather than block). */
void streamRaw() {
  for (uint8_t i = 0; i < 3; i++) rawBuffer[rawInPacket * 3 + i] = lastRaw[i];
  if (++rawInPacket < RAW_SAMPLES_PER_PACKET) return;
  rawInPacket = 0;
  uint8_t payload[2 + RAW_SAMPLES_PER_PACKET * 6];
  payload[0] = (uint8_t)(rawSequence & 0xFF);
  payload[1] = (uint8_t)(rawSequence >> 8);
  for (uint8_t i = 0; i < RAW_SAMPLES_PER_PACKET * 3; i++) {
    payload[2 + 2 * i] = (uint8_t)(rawBuffer[i] & 0xFF);
    payload[3 + 2 * i] = (uint8_t)((uint16_t)rawBuffer[i] >> 8);
  }
  rawSequence++;
  rawCharacteristic.notify(payload, sizeof(payload));
}

bool configureImu() {
  Wire1.begin();
  Wire1.setClock(400000);

  uint8_t whoAmI = 0;
  if (!readRegister(REG_WHO_AM_I, whoAmI) || whoAmI != WHO_AM_I_EXPECTED) {
    return false;
  }

  writeRegister(REG_CTRL3_C, CTRL3_C_SW_RESET);
  delay(20);
  writeRegister(REG_CTRL3_C,   CFG_CTRL3_C);
  writeRegister(REG_CTRL1_XL,  CFG_CTRL1_XL);
  writeRegister(REG_CTRL2_G,   CFG_CTRL2_G);
  writeRegister(REG_INT1_CTRL, CFG_INT1);
  delay(50);
  return true;
}

// ---------------------------------------------------------------------------
// Battery
// ---------------------------------------------------------------------------

// The XIAO measures the LiPo through a 1 MΩ / 510 kΩ divider on PIN_VBAT
// (P0.31), switched by VBAT_ENABLE (P0.14, active low).
static const float VBAT_DIVIDER = (1000.0f + 510.0f) / 510.0f;
static const float ADC_FULL_SCALE_V = 2.4f;     // AR_INTERNAL_2_4
static const float ADC_MAX = 4095.0f;           // 12-bit
static const uint32_t BATTERY_PERIOD_MS = 10000;

// LiPo open-circuit voltage to charge, at rest. The curve is flat in the
// middle and steep at both ends, so a straight line between 3.3 V and 4.2 V
// would read 50 % for most of the session and then collapse.
struct BatteryPoint { float volts; uint8_t percent; };
const BatteryPoint BATTERY_CURVE[] = {
  { 4.20f, 100 }, { 4.15f, 95 }, { 4.11f, 90 }, { 4.08f, 85 }, { 4.02f, 80 },
  { 3.98f,  75 }, { 3.95f, 70 }, { 3.91f, 65 }, { 3.87f, 60 }, { 3.85f, 55 },
  { 3.84f,  50 }, { 3.82f, 45 }, { 3.80f, 40 }, { 3.79f, 35 }, { 3.77f, 30 },
  { 3.75f,  25 }, { 3.73f, 20 }, { 3.71f, 15 }, { 3.69f, 10 }, { 3.61f,  5 },
  { 3.27f,   0 },
};
const uint8_t BATTERY_POINTS = sizeof(BATTERY_CURVE) / sizeof(BATTERY_CURVE[0]);

float batteryVolts = 0.0f;
bool  batteryPrimed = false;
uint8_t batteryPercent = 0;
uint32_t lastBatteryMs = 0;

void setupBattery() {
  // The divider stays enabled for good. Seeed warns that driving P0.14 HIGH
  // while the battery charges can put the full battery voltage on P0.31 and
  // damage it; enabled, the divider only draws about 3 µA.
  pinMode(VBAT_ENABLE, OUTPUT);
  digitalWrite(VBAT_ENABLE, LOW);
  analogReference(AR_INTERNAL_2_4);
  analogReadResolution(12);
  // The divider is a ~340 kΩ source (1 MΩ ∥ 510 kΩ). The core's default
  // 3 µs acquisition is meant for 10 kΩ or less: the sampling capacitor does
  // not settle, so the reading comes out low and changes from one
  // measurement to the next. The nRF52840 needs 40 µs for up to 800 kΩ.
  analogSampleTime(40);
}

float readBatteryVolts() {
  // Averaging smooths out the noise the radio puts on the ADC. The first
  // conversion is dropped: it starts from whatever the sampling capacitor
  // held before.
  analogRead(PIN_VBAT);
  uint32_t sum = 0;
  for (uint8_t i = 0; i < 32; i++) sum += analogRead(PIN_VBAT);
  return (sum / 32.0f) * ADC_FULL_SCALE_V / ADC_MAX * VBAT_DIVIDER;
}

uint8_t percentFromVolts(float volts) {
  if (volts >= BATTERY_CURVE[0].volts) return 100;
  for (uint8_t i = 1; i < BATTERY_POINTS; i++) {
    const BatteryPoint &hi = BATTERY_CURVE[i - 1];
    const BatteryPoint &lo = BATTERY_CURVE[i];
    if (volts >= lo.volts) {
      float t = (volts - lo.volts) / (hi.volts - lo.volts);
      return (uint8_t)(lo.percent + t * (hi.percent - lo.percent) + 0.5f);
    }
  }
  return 0;
}

/* Measures every BATTERY_PERIOD_MS and publishes only when the level changes. */
void updateBattery(uint32_t nowMs, bool force) {
  if (!force && nowMs - lastBatteryMs < BATTERY_PERIOD_MS) return;
  lastBatteryMs = nowMs;

  float volts = readBatteryVolts();
  // Slow average: a heavy rep sags the voltage for a moment, and the level
  // on the phone should not jump around with it.
  batteryVolts = batteryPrimed ? batteryVolts + 0.3f * (volts - batteryVolts) : volts;
  batteryPrimed = true;

  uint8_t percent = percentFromVolts(batteryVolts);
  // The middle of the LiPo curve is flat (about 1 % per 3 mV), so a few mV
  // of noise would flip the level back and forth. Publish only real changes.
  int delta = (int)percent - (int)batteryPercent;
  if (force || delta >= 2 || delta <= -2) {
    batteryPercent = percent;
    batteryService.write(percent);
    if (Bluefruit.connected()) batteryService.notify(percent);
  }
}

// ---------------------------------------------------------------------------
// Counting
// ---------------------------------------------------------------------------

void resetSession(bool alsoDropReference) {
  repCount = 0;
  inUpPhase = false;
  stackCounter.reset();
  tiltCounter.reset();
  if (alsoDropReference) {
    referenceCaptured = false;
    stillSinceMs = 0;
  }
}

/* Angle between the current gravity estimate and the captured reference. */
float angleFromReferenceDeg() {
  float currentNorm = sqrtf(gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ);
  float refNorm = sqrtf(referenceX * referenceX + referenceY * referenceY + referenceZ * referenceZ);
  if (currentNorm < 0.01f || refNorm < 0.01f) return 0.0f;

  float dot = (gravityX * referenceX + gravityY * referenceY + gravityZ * referenceZ)
            / (currentNorm * refNorm);
  if (dot > 1.0f) dot = 1.0f;
  if (dot < -1.0f) dot = -1.0f;

  return acosf(dot) * 57.29578f;
}

/*
 * Profiles 2 and 3. Follows the vertical velocity, sample by sample, and
 * records it for the end-of-set analysis. The published "angle" carries that
 * velocity in cm/s so the app can show it.
 */
void updateStack(float ax, float ay, float az, uint32_t nowMs) {
  float refNorm = sqrtf(referenceX * referenceX + referenceY * referenceY + referenceZ * referenceZ);
  if (refNorm < 0.5f) return;

  // The length of the reading minus its length at rest: 1 g plus the vertical
  // acceleration, whichever way the sensor is turned. Projecting on the axis
  // that was vertical at calibration instead lets gravity leak in as soon as
  // the sensor tilts (15 mg at 10°): held in the hand, or slipped on the
  // plate, the velocity drifted away and the count stayed at 0. Horizontal
  // movement only adds its square, and a stack hardly has any.
  float vertical = sqrtf(ax * ax + ay * ay + az * az) - refNorm;
  // Profile 3: upside down, so down-then-up reads as up-then-down and the
  // rep closes at the top. The recording gets the same sign, so the end-of-
  // set analysis sees what the live counter saw.
  const bool fromTop = EXERCISE_PROFILES[currentExercise].fromTop;
  if (fromTop) vertical = -vertical;

  setRecorder.push(vertical);
  if (stackCounter.update(vertical, nowMs)) {
    repCount = stackCounter.reps;
    digitalWrite(LED_BUILTIN, LOW);     // active low: LOW = on
    ledOffAtMs = nowMs + 120;
  }

  // The app gets the real direction: positive is up either way. On a press
  // the lifting half is the counter's way down.
  float velocity = fromTop ? -stackCounter.velocity : stackCounter.velocity;
  inUpPhase = fromTop ? velocity > 0.05f : stackCounter.lifting();
  currentAngleDeg = velocity * 100.0f;   // cm/s
}

/* Tilt profiles: the waves of the angle from the calibration pose. */
void updateCounter(uint32_t nowMs) {
  if (tiltCounter.update(currentAngleDeg, nowMs)) {
    repCount = tiltCounter.reps;
    digitalWrite(LED_BUILTIN, LOW);     // active low: LOW = on
    ledOffAtMs = nowMs + 120;
  }
  inUpPhase = tiltCounter.lifting();
}

// ---------------------------------------------------------------------------
// BLE
// ---------------------------------------------------------------------------

void onControlWrite(uint16_t connectionHandle, BLECharacteristic *characteristic,
                    uint8_t *data, uint16_t length) {
  (void)connectionHandle;
  (void)characteristic;
  if (length < 1) return;

  uint8_t next = (commandHead + 1) % COMMAND_QUEUE;
  if (next == commandTail) return;   // full: the app resends what matters
  commandQueue[commandHead][0] = data[0];
  commandQueue[commandHead][1] = length >= 2 ? data[1] : 0;
  commandHead = next;
}

/* End of set: stop recording, analyse, and answer with both counts. */
void analyzeSet(uint8_t token) {
  setRecorder.stop();
  uint8_t status = ANALYSIS_OK;
  uint16_t found = 0;
  if (EXERCISE_PROFILES[currentExercise].kind != PROFILE_STACK || setRecorder.length < 2) {
    status = ANALYSIS_UNAVAILABLE;
  } else {
    if (setRecorder.truncated) status = ANALYSIS_TRUNCATED;
    // Milliseconds of work for a full buffer. It consumes the recording,
    // which is fine: the set is closed.
    found = stack::analyzeSet(setRecorder.samples, setRecorder.length, analysisWorkspace,
                              stackCounter.tuning);
    setRecorder.length = 0;
  }

  uint8_t payload[8];
  payload[0] = ANALYSIS_VERSION;
  payload[1] = token;
  payload[2] = status;
  payload[3] = (uint8_t)(found & 0xFF);
  payload[4] = (uint8_t)(found >> 8);
  payload[5] = (uint8_t)(repCount & 0xFF);
  payload[6] = (uint8_t)(repCount >> 8);
  payload[7] = 0;
  analysisCharacteristic.write(payload, sizeof(payload));
  analysisCharacteristic.notify(payload, sizeof(payload));
}

void applyCommands() {
  while (commandTail != commandHead) {
    uint8_t command = commandQueue[commandTail][0];
    uint8_t argument = commandQueue[commandTail][1];
    commandTail = (commandTail + 1) % COMMAND_QUEUE;

    switch (command) {
      case CMD_SET_EXERCISE:
        if (argument < EXERCISE_COUNT) {
          currentExercise = argument;
          resetSession(true);   // counter and resting pose both change
          setRecorder.stop();
        }
        break;
      case CMD_RESET_COUNT:
        resetSession(false);
        // A new set starts: record it, so it can be analysed when it closes.
        if (EXERCISE_PROFILES[currentExercise].kind == PROFILE_STACK) setRecorder.start();
        break;
      case CMD_REZERO:
        resetSession(true);
        setRecorder.stop();
        break;
      case CMD_ANALYZE:
        analyzeSet(argument);
        break;
      case CMD_SET_GRIP_LIFT:
        // The count follows the period of the curve now; there is no
        // minimum travel to raise.
        break;
      case CMD_SET_SENSITIVITY:
        // Applies from the next sample, mid-set too; reset() keeps it.
        setSensitivity(argument);
        break;
      case CMD_SET_RAW_STREAM:
        rawInPacket = 0;
        rawStreaming = argument != 0;
        break;
      default:
        break;
    }
  }
}

void onDisconnect(uint16_t connectionHandle, uint8_t reason) {
  (void)connectionHandle;
  (void)reason;
  rawStreaming = false;   // the next app asks again if it wants it
}

void onConnect(uint16_t connectionHandle) {
  (void)connectionHandle;
  // Through the queue as well: a rezero, like the app would ask for.
  uint8_t next = (commandHead + 1) % COMMAND_QUEUE;
  if (next == commandTail) return;
  commandQueue[commandHead][0] = CMD_REZERO;
  commandQueue[commandHead][1] = 0;
  commandHead = next;
}

void publishState(uint32_t nowMs) {
  // 6 bytes, little endian: count, angle in tenths of a degree, exercise, phase.
  // Profiles 2 and 3 send the stack's vertical velocity in tenths of cm/s instead
  // of the angle (positive = up).
  uint8_t payload[6];
  int16_t angleTenths = (int16_t)(currentAngleDeg * 10.0f);

  payload[0] = (uint8_t)(repCount & 0xFF);
  payload[1] = (uint8_t)(repCount >> 8);
  payload[2] = (uint8_t)(angleTenths & 0xFF);
  payload[3] = (uint8_t)((angleTenths >> 8) & 0xFF);
  payload[4] = currentExercise;
  // bit 0: in the up phase. bit 1: reference captured, so the app can tell
  // "hold still" apart from "ready".
  payload[5] = (uint8_t)((inUpPhase ? 0x01 : 0x00) | (referenceCaptured ? 0x02 : 0x00));

  stateCharacteristic.notify(payload, sizeof(payload));
  lastNotifyMs = nowMs;
}

void startBle() {
  // Larger MTU and notification queue: developer mode streams about 35
  // packets a second on top of the state.
  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("RepCounter");
  Bluefruit.Periph.setConnectCallback(onConnect);
  Bluefruit.Periph.setDisconnectCallback(onDisconnect);

  repService.begin();

  stateCharacteristic.setProperties(CHR_PROPS_NOTIFY | CHR_PROPS_READ);
  stateCharacteristic.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  stateCharacteristic.setFixedLen(6);
  stateCharacteristic.begin();

  controlCharacteristic.setProperties(CHR_PROPS_WRITE | CHR_PROPS_WRITE_WO_RESP);
  controlCharacteristic.setPermission(SECMODE_NO_ACCESS, SECMODE_OPEN);
  controlCharacteristic.setMaxLen(4);
  controlCharacteristic.setWriteCallback(onControlWrite);
  controlCharacteristic.begin();

  analysisCharacteristic.setProperties(CHR_PROPS_NOTIFY | CHR_PROPS_READ);
  analysisCharacteristic.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  analysisCharacteristic.setFixedLen(8);
  analysisCharacteristic.begin();

  rawCharacteristic.setProperties(CHR_PROPS_NOTIFY);
  rawCharacteristic.setPermission(SECMODE_OPEN, SECMODE_NO_ACCESS);
  rawCharacteristic.setFixedLen(2 + RAW_SAMPLES_PER_PACKET * 6);
  rawCharacteristic.begin();

  batteryService.begin();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(repService);
  Bluefruit.ScanResponse.addName();

  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

bool imuReady = false;

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH);       // active low: HIGH = off
  pinMode(PIN_LSM6DS3TR_C_INT1, INPUT);

  powerImuWithHighDrive();
  delay(200);

  imuReady = configureImu();
  startBle();

  setupBattery();
  updateBattery(millis(), true);
}

void loop() {
  uint32_t nowMs = millis();

  if (ledOffAtMs != 0 && nowMs >= ledOffAtMs) {
    digitalWrite(LED_BUILTIN, HIGH);
    ledOffAtMs = 0;
  }

  updateBattery(nowMs, false);
  applyCommands();

  if (!imuReady) {
    // Slow double blink means the sensor never came up.
    digitalWrite(LED_BUILTIN, (nowMs % 2000) < 100 ? LOW : HIGH);
    return;
  }

  if (digitalRead(PIN_LSM6DS3TR_C_INT1) == HIGH) {
    float ax, ay, az;
    if (readAccel(ax, ay, az)) {
      if (rawStreaming && Bluefruit.connected()) streamRaw();
      if (!filterPrimed) {
        gravityX = ax; gravityY = ay; gravityZ = az;
        filterPrimed = true;
      } else {
        gravityX += FILTER_ALPHA * (ax - gravityX);
        gravityY += FILTER_ALPHA * (ay - gravityY);
        gravityZ += FILTER_ALPHA * (az - gravityZ);
      }

      if (!referenceCaptured) {
        // The resting pose is captured automatically after a second of
        // stillness, so the user never has to press anything to start.
        float deviation = fabsf(ax - gravityX) + fabsf(ay - gravityY) + fabsf(az - gravityZ);
        stillnessAccumulator += 0.05f * (deviation - stillnessAccumulator);

        if (stillnessAccumulator < 0.02f) {
          if (stillSinceMs == 0) {
            stillSinceMs = nowMs;
          } else if (nowMs - stillSinceMs > 1000) {
            referenceX = gravityX;
            referenceY = gravityY;
            referenceZ = gravityZ;
            referenceCaptured = true;
          }
        } else {
          stillSinceMs = 0;
        }
      } else if (EXERCISE_PROFILES[currentExercise].kind == PROFILE_STACK) {
        updateStack(ax, ay, az, nowMs);
      } else {
        currentAngleDeg = angleFromReferenceDeg();
        updateCounter(nowMs);
      }
    }
  }

  // 20 Hz is smooth to watch and leaves the radio mostly idle.
  if (Bluefruit.connected() && (nowMs - lastNotifyMs >= 50)) {
    publishState(nowMs);
  }
}
