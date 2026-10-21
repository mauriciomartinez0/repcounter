// Link to the XIAO nRF52840 Sense.
//
// The counting happens on the board, not here. The app selects the exercise,
// resets the count, and displays state. That split keeps counting working even
// if the phone screen locks or the connection drops for a moment.
//
// `SensorService` holds the state screens observe. A driver talks to the real
// board (`BleSensorDriver`) or fakes it (`SimulatedSensorDriver`, enabled with
// SensorSimulated in Info.plist) so every screen can be tried without hardware.

import CoreBluetooth
import Foundation
import Observation

// Must match the firmware.
let kServiceUuid = CBUUID(string: "a1b20001-7f3c-4e8d-9a6b-2c5d8e0f1a3b")
let kStateUuid = CBUUID(string: "a1b20002-7f3c-4e8d-9a6b-2c5d8e0f1a3b")
let kControlUuid = CBUUID(string: "a1b20003-7f3c-4e8d-9a6b-2c5d8e0f1a3b")
/// End-of-set analysis (weight-stack profile). Optional: older firmware
/// does not have it.
let kAnalysisUuid = CBUUID(string: "a1b20004-7f3c-4e8d-9a6b-2c5d8e0f1a3b")

// Standard Battery Service. Optional: firmware without it just shows no level.
let kBatteryServiceUuid = CBUUID(string: "180F")
let kBatteryLevelUuid = CBUUID(string: "2A19")

let kCmdSetExercise: UInt8 = 0x01
let kCmdResetCount: UInt8 = 0x02
let kCmdRezero: UInt8 = 0x03
let kCmdAnalyze: UInt8 = 0x04
let kCmdSetGripLift: UInt8 = 0x05

/// Upper end of `SensorService.setGripLift`; the firmware caps it the same.
let kMaxGripLiftCm = 30

/// Everything the board publishes in one notification.
///
/// Bytes 0–5 are what the current firmware sends. Bytes 6–7 are optional:
/// the mean velocity of the last rep in mm/s, which the rest screen and the
/// history show. Firmware that does not send them still works; the velocity
/// just shows as "—".
struct DeviceState: Equatable {
    var repCount: Int
    var angleDegrees: Double
    var exerciseId: Int
    var inUpPhase: Bool

    /// False while the board is still waiting for a second of stillness to
    /// learn the resting pose. Until then it cannot count anything.
    var referenceCaptured: Bool

    /// m/s, nil when the firmware does not report it.
    var lastRepVelocity: Double?

    static let empty = DeviceState(
        repCount: 0, angleDegrees: 0, exerciseId: 0, inUpPhase: false, referenceCaptured: false)

    static func parse(_ data: Data) -> DeviceState? {
        // A sliced Data is not 0-indexed; an array is.
        let b = [UInt8](data)
        guard b.count >= 6 else { return nil }
        var velocity: Double?
        if b.count >= 8 {
            let mmPerSecond = UInt16(b[6]) | UInt16(b[7]) << 8
            if mmPerSecond > 0 { velocity = Double(mmPerSecond) / 1000 }
        }
        return DeviceState(
            repCount: Int(UInt16(b[0]) | UInt16(b[1]) << 8),
            angleDegrees: Double(Int16(bitPattern: UInt16(b[2]) | UInt16(b[3]) << 8)) / 10,
            exerciseId: Int(b[4]),
            inUpPhase: b[5] & 0x01 != 0,
            referenceCaptured: b[5] & 0x02 != 0,
            lastRepVelocity: velocity
        )
    }
}

/// What the board found when it analysed the set that just closed.
struct SetAnalysis: Equatable {
    enum Status: UInt8 {
        case ok = 0
        /// The set ran past the board's buffer; only its start was analysed.
        case truncated = 1
        /// Not the weight-stack profile, or nothing was recorded.
        case unavailable = 2
    }

    let status: Status
    /// Reps the analysis found.
    let found: Int
    /// The live count when the set closed.
    let live: Int

    /// Version 1 packet: version, token, status, found (u16), live (u16).
    static func parse(_ data: Data) -> (token: UInt8, analysis: SetAnalysis)? {
        let b = [UInt8](data)
        guard b.count >= 7, b[0] == 1, let status = Status(rawValue: b[2]) else { return nil }
        return (b[1], SetAnalysis(status: status, found: Int(UInt16(b[3]) | UInt16(b[4]) << 8),
                                  live: Int(UInt16(b[5]) | UInt16(b[6]) << 8)))
    }
}

enum SensorStatus { case idle, scanning, connecting, ready, failed }

enum SensorFailure { case notFound, lost, unsupported, error }

@MainActor
protocol SensorDriver: AnyObject {
    func connect()
    func cancel()
    func send(_ bytes: [UInt8])
    func setExercise(_ profile: Int)
    func resetCount()
    func rezero()
    func setGripLift(_ cm: Int)
    /// Whether the board can analyse a set when it closes.
    var supportsSetAnalysis: Bool { get }
    func analyzeSet(token: UInt8)
}

@MainActor
@Observable
final class SensorService {
    private(set) var status: SensorStatus = .idle
    private(set) var failure: SensorFailure?
    /// Technical detail of the last failure, for the error screen.
    private(set) var detail = ""
    private(set) var state = DeviceState.empty
    /// Charge of the board's battery, 0–100. Nil while disconnected or when
    /// the firmware does not publish it.
    private(set) var batteryLevel: Int?

    @ObservationIgnored private var listeners: [UUID: () -> Void] = [:]
    @ObservationIgnored private var driver: SensorDriver!
    @ObservationIgnored private var analysisToken: UInt8 = 0
    @ObservationIgnored private var analysisWaiter: (token: UInt8, resume: (SetAnalysis?) -> Void)?

    var connected: Bool { status == .ready }
    var busy: Bool { status == .scanning || status == .connecting }

    init(simulated: Bool) {
        if simulated {
            driver = SimulatedSensorDriver(service: self)
        } else {
            driver = BleSensorDriver(service: self)
        }
    }

    /// Called after every change, like a ChangeNotifier listener. The
    /// workout reacts to the board through this.
    func addListener(_ listener: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeListener(_ id: UUID?) {
        if let id { listeners.removeValue(forKey: id) }
    }

    private func notify() {
        for listener in Array(listeners.values) { listener() }
    }

    func connect() { driver.connect() }
    func cancel() { driver.cancel() }
    func setExercise(_ firmwareProfile: Int) { driver.setExercise(firmwareProfile) }
    func resetCount() { driver.resetCount() }

    /// Forget the resting pose and learn it again. The board clears
    /// `referenceCaptured` until the user holds still.
    func rezero() { driver.rezero() }

    /// Weight stack only: how many cm the stack rises when the user takes the
    /// handle. The board then ignores moves of that size, so taking the handle
    /// or letting it go does not count as a rep. Firmware without the command
    /// ignores it.
    func setGripLift(_ cm: Int) { driver.setGripLift(min(kMaxGripLiftCm, max(0, cm))) }

    var supportsSetAnalysis: Bool { connected && driver.supportsSetAnalysis }

    /// Closes the set on the board and waits for its analysis. Nil when the
    /// board cannot do it, the answer does not come in time, or the link drops.
    func analyzeSet(timeout: Duration = .seconds(4)) async -> SetAnalysis? {
        guard supportsSetAnalysis else { return nil }
        analysisWaiter?.resume(nil)
        analysisToken &+= 1
        let token = analysisToken
        return await withCheckedContinuation { continuation in
            var done = false
            let finish: (SetAnalysis?) -> Void = { result in
                guard !done else { return }
                done = true
                continuation.resume(returning: result)
            }
            analysisWaiter = (token, finish)
            driver.analyzeSet(token: token)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.analysisWaiter?.token == token else { return }
                self.analysisWaiter = nil
                finish(nil)
            }
        }
    }

    fileprivate func deliverAnalysis(token: UInt8, _ analysis: SetAnalysis) {
        guard let waiter = analysisWaiter, waiter.token == token else { return }
        analysisWaiter = nil
        waiter.resume(analysis)
    }

    fileprivate func set(_ status: SensorStatus, _ failure: SensorFailure? = nil, _ detail: String = "") {
        self.status = status
        self.failure = failure
        self.detail = detail
        if status != .ready {
            batteryLevel = nil
            if let waiter = analysisWaiter {
                analysisWaiter = nil
                waiter.resume(nil)
            }
        }
        notify()
    }

    fileprivate func setBattery(_ level: Int?) {
        batteryLevel = level.map { min(100, max(0, $0)) }
    }

    fileprivate func publish(_ state: DeviceState) {
        self.state = state
        notify()
    }
}

// MARK: - Bluetooth

@MainActor
final class BleSensorDriver: NSObject, SensorDriver {
    private weak var service: SensorService?
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var stateCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var analysisCharacteristic: CBCharacteristic?
    private var exerciseId = 0
    private var gripLiftCm = 0
    private var wantsScan = false
    private var scanTimeout: Task<Void, Never>?
    private var connectTimeout: Task<Void, Never>?

    init(service: SensorService) {
        self.service = service
    }

    private var status: SensorStatus { service?.status ?? .idle }

    private func set(_ status: SensorStatus, _ failure: SensorFailure? = nil, _ detail: String = "") {
        service?.set(status, failure, detail)
    }

    func connect() {
        guard let service, !service.busy, !service.connected else { return }
        set(.scanning)
        wantsScan = true
        if let central {
            startScanIfReady(central)
        } else {
            // Created on first use, so the Bluetooth permission prompt appears
            // when the user taps "Conectar".
            central = CBCentralManager(delegate: self, queue: nil)
        }
    }

    private func startScanIfReady(_ central: CBCentralManager) {
        guard wantsScan, status == .scanning else { return }
        switch central.state {
        case .unknown, .resetting:
            return // didUpdateState calls back.
        case .unsupported:
            wantsScan = false
            set(.failed, .unsupported, "Este teléfono no soporta Bluetooth LE.")
        case .unauthorized:
            wantsScan = false
            set(.failed, .error, "Rep Counter no tiene permiso para usar Bluetooth. Actívalo en Ajustes.")
        case .poweredOff:
            wantsScan = false
            set(.failed, .error, "El Bluetooth del teléfono está apagado.")
        case .poweredOn:
            wantsScan = false
            central.scanForPeripherals(withServices: [kServiceUuid], options: nil)
            // If the scan window closes without a hit, say so instead of hanging.
            scanTimeout?.cancel()
            scanTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(16))
                guard let self, !Task.isCancelled else { return }
                self.central?.stopScan()
                if self.status == .scanning { self.set(.failed, .notFound) }
            }
        @unknown default:
            return
        }
    }

    private func connectTo(_ peripheral: CBPeripheral) {
        set(.connecting)
        self.peripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral, options: nil)
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.status == .connecting else { return }
            self.central?.cancelPeripheralConnection(peripheral)
            self.set(.failed, .error, "El sensor no respondió a tiempo.")
        }
    }

    private func fail(_ message: String) {
        connectTimeout?.cancel()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        set(.failed, .error, message)
    }

    func cancel() {
        wantsScan = false
        scanTimeout?.cancel()
        connectTimeout?.cancel()
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        set(.idle)
    }

    func send(_ bytes: [UInt8]) {
        guard let peripheral, let control = controlCharacteristic, status == .ready else { return }
        // A dropped command is not worth interrupting a set for; the next
        // notification will show whether it landed.
        peripheral.writeValue(Data(bytes), for: control, type: .withResponse)
    }

    func setExercise(_ profile: Int) {
        exerciseId = profile
        send([kCmdSetExercise, UInt8(clamping: profile)])
    }

    func resetCount() { send([kCmdResetCount]) }
    func rezero() { send([kCmdRezero]) }

    func setGripLift(_ cm: Int) {
        gripLiftCm = cm
        send([kCmdSetGripLift, UInt8(clamping: cm)])
    }

    var supportsSetAnalysis: Bool { analysisCharacteristic != nil }

    func analyzeSet(token: UInt8) { send([kCmdAnalyze, token]) }
}

extension BleSensorDriver: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            startScanIfReady(central)
            if central.state != .poweredOn && status == .ready {
                set(.failed, .lost)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard status == .scanning else { return }
            scanTimeout?.cancel()
            central.stopScan()
            connectTo(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([kServiceUuid, kBatteryServiceUuid])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            guard status == .connecting else { return }
            fail(error?.localizedDescription ?? "No se pudo conectar con el sensor.")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            stateCharacteristic = nil
            controlCharacteristic = nil
            analysisCharacteristic = nil
            if status == .ready {
                set(.failed, .lost)
            } else if status == .connecting {
                fail(error?.localizedDescription ?? "Se cortó la conexión con el sensor.")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard status == .connecting else { return }
            if let battery = peripheral.services?.first(where: { $0.uuid == kBatteryServiceUuid }) {
                peripheral.discoverCharacteristics([kBatteryLevelUuid], for: battery)
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == kServiceUuid }) else {
                fail("El servicio no está en este dispositivo")
                return
            }
            peripheral.discoverCharacteristics([kStateUuid, kControlUuid, kAnalysisUuid], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            if service.uuid == kBatteryServiceUuid {
                // Read once now, then follow the board's notifications.
                if let level = service.characteristics?.first(where: { $0.uuid == kBatteryLevelUuid }) {
                    peripheral.readValue(for: level)
                    if level.properties.contains(.notify) { peripheral.setNotifyValue(true, for: level) }
                }
                return
            }
            guard status == .connecting else { return }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == kStateUuid {
                    stateCharacteristic = characteristic
                } else if characteristic.uuid == kControlUuid {
                    controlCharacteristic = characteristic
                } else if characteristic.uuid == kAnalysisUuid {
                    analysisCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            guard let state = stateCharacteristic, controlCharacteristic != nil else {
                fail("Faltan características en el servicio")
                return
            }
            peripheral.setNotifyValue(true, for: state)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard status == .connecting, characteristic.uuid == kStateUuid else { return }
            if let error {
                fail(error.localizedDescription)
                return
            }
            connectTimeout?.cancel()
            set(.ready)
            // After a reconnect the board may have restarted; tell it again what
            // we are counting.
            setExercise(exerciseId)
            setGripLift(gripLiftCm)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            if characteristic.uuid == kBatteryLevelUuid {
                if let byte = characteristic.value?.first { service?.setBattery(Int(byte)) }
                return
            }
            if characteristic.uuid == kAnalysisUuid {
                if let value = characteristic.value, let packet = SetAnalysis.parse(value) {
                    service?.deliverAnalysis(token: packet.token, packet.analysis)
                }
                return
            }
            guard characteristic.uuid == kStateUuid, let value = characteristic.value,
                  let parsed = DeviceState.parse(value)
            else { return }
            service?.publish(parsed)
        }
    }
}

// MARK: - Simulator

/// Fake board: finds itself after a moment, calibrates after a second of
/// "stillness", then does a set of 8–12 reps and waits for the next reset.
@MainActor
final class SimulatedSensorDriver: SensorDriver {
    private weak var service: SensorService?
    private var pending: Task<Void, Never>?
    private var ticker: Timer?

    private var exerciseId = 0
    private var calibrated = false
    private var reps = 0
    private var repsThisSet = 10
    private var phase = 0.0
    private var up = false
    private var velocity: Double?
    private var battery = 87
    private var ticks = 0
    /// Reps the fake board "missed" live; the analysis finds them.
    private var missed = 0

    private static let tick = 0.05
    private static let repSeconds = 2.4
    private static let threshold = 70.0

    init(service: SensorService) {
        self.service = service
    }

    func connect() {
        guard let service, !service.busy, !service.connected else { return }
        service.set(.scanning)
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self, !Task.isCancelled else { return }
            self.service?.set(.ready)
            self.service?.setBattery(self.battery)
            if self.ticker == nil {
                let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.step() }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.ticker = timer
            }
            self.startCalibration()
        }
    }

    func cancel() {
        pending?.cancel()
        ticker?.invalidate()
        ticker = nil
        service?.set(.idle)
    }

    private func startCalibration() {
        calibrated = false
        phase = 0
        publish(0)
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard let self, !Task.isCancelled else { return }
            self.calibrated = true
            self.publish(0)
        }
    }

    private func step() {
        // One percent every two minutes, so the badge visibly changes.
        ticks += 1
        if ticks % 2400 == 0 && battery > 0 {
            battery -= 1
            service?.setBattery(battery)
        }
        let finished = reps + missed >= repsThisSet
        if !calibrated || (finished && phase == 0) { return }
        phase += Self.tick / Self.repSeconds
        // After the last rep, finish lowering and then stay at rest.
        if finished && phase - phase.rounded(.down) < 0.03 {
            phase = 0
            publish(0)
            return
        }
        let angle = 43 - 43 * cos(2 * .pi * phase)
        if !up && angle >= Self.threshold {
            up = true
            // On the weight stack, now and then a rep slips past the live
            // count, so the end-of-set review can be tried without the board.
            if exerciseId == 2 && reps > 0 && Double.random(in: 0..<1) < 0.2 {
                missed += 1
            } else {
                reps += 1
            }
            velocity = 0.40 + Double.random(in: 0..<0.12)
        } else if up && angle < Self.threshold - 10 {
            up = false
        }
        publish(angle)
    }

    var supportsSetAnalysis: Bool { true }

    func analyzeSet(token: UInt8) {
        let analysis = exerciseId == 2
            ? SetAnalysis(status: .ok, found: reps + missed, live: reps)
            : SetAnalysis(status: .unavailable, found: 0, live: reps)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.service?.deliverAnalysis(token: token, analysis)
        }
    }

    private func publish(_ angle: Double) {
        service?.publish(DeviceState(
            repCount: reps, angleDegrees: angle, exerciseId: exerciseId,
            inUpPhase: up, referenceCaptured: calibrated, lastRepVelocity: velocity))
    }

    func send(_ bytes: [UInt8]) {}

    func setExercise(_ profile: Int) { exerciseId = profile }

    func setGripLift(_ cm: Int) {}

    func resetCount() {
        reps = 0
        missed = 0
        phase = 0
        up = false
        velocity = nil
        repsThisSet = 8 + Int.random(in: 0..<5)
        publish(0)
    }

    func rezero() {
        resetCount()
        startCalibration()
    }
}
