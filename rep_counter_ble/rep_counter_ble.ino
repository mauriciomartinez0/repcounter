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
 *   4. Count with a hysteresis state machine plus a refractory period.
 *
 * The gyroscope is powered down: it contributes nothing here and costs power.
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

BLEService        repService(UUID_SERVICE);
BLECharacteristic stateCharacteristic(UUID_STATE);
BLECharacteristic controlCharacteristic(UUID_CONTROL);

// Control commands from the app
static const uint8_t CMD_SET_EXERCISE = 0x01;   // payload: exercise id
static const uint8_t CMD_RESET_COUNT  = 0x02;
static const uint8_t CMD_REZERO       = 0x03;

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

struct ExerciseProfile {
  const char *name;
  float enterAngleDeg;        // crossing up past this arms the rep
  float exitAngleDeg;         // coming back below this completes it
  uint32_t refractoryMs;      // ignore anything faster than this
};

// Two profiles, thresholds chosen for the expected range of motion. The gap
// between enter and exit is the hysteresis that stops a wobble at the
// threshold from counting several times.
const ExerciseProfile EXERCISE_PROFILES[] = {
  { "push-up",     25.0f, 12.0f, 500 },   // id 0: sensor on the upper arm
  { "biceps curl", 45.0f, 20.0f, 450 },   // id 1: sensor on the backpack
};
const uint8_t EXERCISE_COUNT = sizeof(EXERCISE_PROFILES) / sizeof(EXERCISE_PROFILES[0]);

uint8_t currentExercise = 0;

// ---------------------------------------------------------------------------
// Runtime state
// ---------------------------------------------------------------------------

float gravityX = 0.0f, gravityY = 0.0f, gravityZ = 1.0f;   // low-passed estimate
bool  filterPrimed = false;

float referenceX = 0.0f, referenceY = 0.0f, referenceZ = 1.0f;
bool  referenceCaptured = false;

uint16_t repCount = 0;
bool     inUpPhase = false;
uint32_t lastRepMs = 0;

float currentAngleDeg = 0.0f;

// Stillness detection, used to capture the reference automatically.
float stillnessAccumulator = 0.0f;
uint32_t stillSinceMs = 0;

uint32_t lastNotifyMs = 0;
uint32_t ledOffAtMs = 0;

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

  ax = rawX * ACCEL_G_PER_COUNT;
  ay = rawY * ACCEL_G_PER_COUNT;
  az = rawZ * ACCEL_G_PER_COUNT;
  return true;
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
// Counting
// ---------------------------------------------------------------------------

void resetSession(bool alsoDropReference) {
  repCount = 0;
  inUpPhase = false;
  lastRepMs = 0;
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

void updateCounter(uint32_t nowMs) {
  const ExerciseProfile &profile = EXERCISE_PROFILES[currentExercise];

  if (!inUpPhase) {
    if (currentAngleDeg >= profile.enterAngleDeg) {
      inUpPhase = true;
    }
    return;
  }

  if (currentAngleDeg <= profile.exitAngleDeg) {
    inUpPhase = false;
    // A rep is only counted on the way back, and only if enough time has
    // passed. Both guards exist because a single shake would otherwise cross
    // both thresholds and register as a rep.
    if (nowMs - lastRepMs >= profile.refractoryMs) {
      repCount++;
      lastRepMs = nowMs;
      digitalWrite(LED_BUILTIN, LOW);     // active low: LOW = on
      ledOffAtMs = nowMs + 120;
    }
  }
}

// ---------------------------------------------------------------------------
// BLE
// ---------------------------------------------------------------------------

void onControlWrite(uint16_t connectionHandle, BLECharacteristic *characteristic,
                    uint8_t *data, uint16_t length) {
  (void)connectionHandle;
  (void)characteristic;
  if (length < 1) return;

  switch (data[0]) {
    case CMD_SET_EXERCISE:
      if (length >= 2 && data[1] < EXERCISE_COUNT) {
        currentExercise = data[1];
        resetSession(true);   // thresholds and resting pose both change
      }
      break;
    case CMD_RESET_COUNT:
      resetSession(false);
      break;
    case CMD_REZERO:
      resetSession(true);
      break;
    default:
      break;
  }
}

void onConnect(uint16_t connectionHandle) {
  (void)connectionHandle;
  resetSession(true);
}

void publishState(uint32_t nowMs) {
  // 6 bytes, little endian: count, angle in tenths of a degree, exercise, phase.
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
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("RepCounter");
  Bluefruit.Periph.setConnectCallback(onConnect);

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
}

void loop() {
  uint32_t nowMs = millis();

  if (ledOffAtMs != 0 && nowMs >= ledOffAtMs) {
    digitalWrite(LED_BUILTIN, HIGH);
    ledOffAtMs = 0;
  }

  if (!imuReady) {
    // Slow double blink means the sensor never came up.
    digitalWrite(LED_BUILTIN, (nowMs % 2000) < 100 ? LOW : HIGH);
    return;
  }

  if (digitalRead(PIN_LSM6DS3TR_C_INT1) == HIGH) {
    float ax, ay, az;
    if (readAccel(ax, ay, az)) {
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
