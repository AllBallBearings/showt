import CoreMotion
import Foundation
import UIKit

// One frame of recorded sensor + computed data
struct MotionSample {
    let timestamp: TimeInterval      // seconds since recording started
    let gravityX: Double             // raw gravity vector
    let gravityY: Double
    let gravityZ: Double
    let userAccelX: Double           // user acceleration (gravity removed)
    let userAccelY: Double
    let userAccelZ: Double
    let roll: Double                 // attitude in radians
    let pitch: Double
    let yaw: Double
    let rotationRateX: Double        // gyro
    let rotationRateY: Double
    let rotationRateZ: Double
    // Computed values from MotionManager
    let rawTilt: Double              // gravity.x fed into updatePosition
    let relativeTilt: Double         // after subtracting centerTilt
    let filteredTilt: Double         // after low-pass
    let filteredTiltVelocity: Double // derivative of filteredTilt
    let sweepPhase: Double           // 0..1 phase
    let currentPosition: Double      // mapped position
    let motionSpeed: Double          // normalized speed 0..1
    // Display state (set by the view each frame)
    let displayTiltNorm: Double      // normalized tilt [0..1] used for column mapping
    let displayTextX: Double         // horizontal pixel offset of text on screen
    let displayTextY: Double         // vertical pixel offset (includes arc)
    let displayArcDrop: Double       // arc vertical offset component
    let displayOpacity: Double       // rendered slit opacity
}

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let stillnessThreshold: Double = 0.02
    private let stillnessDuration: TimeInterval = 1.0
    private let baseTiltSmoothing: Double = 0.16
    private let fastTiltSmoothing: Double = 0.52
    private let velocityForFastResponse: Double = 0.020
    private let maxPosition: Double = 500.0
    private let speedSmoothing: Double = 0.2
    private let maxSpeedForNormalization: Double = 0.12
    private let phaseVelocityScale: Double = 22.0
    private let phaseVelocitySmoothing: Double = 0.35

    @Published var currentPosition: Double = 0.0
    @Published var isStill: Bool = false
    @Published var motionSpeed: Double = 0.0
    @Published var sweepPhase: Double = 0.5
    @Published var isRecording: Bool = false
    @Published var tiltPosition: Double = 0.0  // filteredTilt exposed for direct mapping
    @Published var tiltVelocity: Double = 0.0  // filtered tilt delta per frame
    @Published var verticalTiltPosition: Double = 0.0
    @Published var verticalTiltVelocity: Double = 0.0

    private var lastStillTime: Date?
    private var centerTilt: Double?
    private var filteredTilt: Double = 0.0
    private var filteredSpeed: Double = 0.0
    private var lastFilteredTilt: Double?
    private var lastRelativeTiltForSmoothing: Double?
    private var filteredTiltVelocity: Double = 0.0
    private var filteredVerticalTilt: Double = 0.0
    private var filteredVerticalTiltVelocity: Double = 0.0
    private var lastFilteredVerticalTilt: Double?
    private var centerVerticalTilt: Double?

    // Recording state
    private var recordingStartTime: TimeInterval?
    private(set) var recordedSamples: [MotionSample] = []
    private var lastRawTilt: Double = 0.0
    private var lastRelativeTilt: Double = 0.0

    // Display state — set by the view each frame for recording
    private var displayTiltNorm: Double = 0.5
    private var displayTextX: Double = 0.0
    private var displayTextY: Double = 0.0
    private var displayArcDrop: Double = 0.0
    private var displayOpacity: Double = 0.0

    // Simulator mock motion
    #if targetEnvironment(simulator)
    private var mockTimer: Timer?
    private var mockTime: Double = 0.0
    #endif
    
    init() {
        setupMotionManager()
    }
    
    private func setupMotionManager() {
        motionManager.accelerometerUpdateInterval = 1.0 / 60.0
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
    }
    
    func startMotionUpdates() {
        resetRuntimeState()

        #if targetEnvironment(simulator)
        startMockMotion()
        #else
        guard motionManager.isDeviceMotionAvailable else {
            startAccelerometerFallback()
            return
        }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] deviceMotion, error in
            guard let self = self, let motion = deviceMotion else { return }
            self.updatePosition(withTilt: motion.gravity.x)
            // Negate gravity.z: forward tilt (phone facing ground) gives negative z,
            // but we want positive = looking down so the sign exits at the top.
            self.updateVerticalTilt(withRaw: -motion.gravity.z)
            self.checkStillness(userAcceleration: motion.userAcceleration)
            if self.isRecording {
                self.recordSample(motion: motion)
            }
        }
        #endif
    }
    
    func stopMotionUpdates() {
        #if targetEnvironment(simulator)
        mockTimer?.invalidate()
        mockTimer = nil
        #else
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        #endif
    }
    
    private func resetRuntimeState() {
        currentPosition = 0.0
        isStill = false
        motionSpeed = 0.0
        sweepPhase = 0.5
        lastStillTime = nil
        centerTilt = nil
        filteredTilt = 0.0
        tiltPosition = 0.0
        tiltVelocity = 0.0
        filteredSpeed = 0.0
        lastFilteredTilt = nil
        lastRelativeTiltForSmoothing = nil
        filteredTiltVelocity = 0.0
        verticalTiltPosition = 0.0
        verticalTiltVelocity = 0.0
        filteredVerticalTilt = 0.0
        filteredVerticalTiltVelocity = 0.0
        lastFilteredVerticalTilt = nil
        centerVerticalTilt = nil
    }
    
    private func updatePosition(withTilt rawTilt: Double) {
        if centerTilt == nil {
            centerTilt = rawTilt
        }

        guard let centerTilt else { return }
        let relativeTilt = rawTilt - centerTilt
        lastRawTilt = rawTilt
        lastRelativeTilt = relativeTilt

        // Reduce filter lag when swing speed increases so letter timing stays aligned.
        let relativeTiltVelocity: Double
        if let lastRelativeTiltForSmoothing {
            relativeTiltVelocity = relativeTilt - lastRelativeTiltForSmoothing
        } else {
            relativeTiltVelocity = 0.0
        }
        lastRelativeTiltForSmoothing = relativeTilt
        let velocityNorm = min(1.0, abs(relativeTiltVelocity) / velocityForFastResponse)
        let tiltSmoothing = baseTiltSmoothing + (fastTiltSmoothing - baseTiltSmoothing) * velocityNorm

        filteredTilt = filteredTilt + (relativeTilt - filteredTilt) * tiltSmoothing
        tiltPosition = filteredTilt

        if let lastFilteredTilt {
            let rawVelocity = filteredTilt - lastFilteredTilt
            filteredTiltVelocity = filteredTiltVelocity + (rawVelocity - filteredTiltVelocity) * phaseVelocitySmoothing

            let phaseDelta = filteredTiltVelocity * phaseVelocityScale
            sweepPhase += phaseDelta

            if sweepPhase >= 1.0 {
                sweepPhase = 1.0
                filteredTiltVelocity *= -0.3
            } else if sweepPhase <= 0.0 {
                sweepPhase = 0.0
                filteredTiltVelocity *= -0.3
            }
        } else {
            filteredTiltVelocity = 0.0
        }

        tiltVelocity = filteredTiltVelocity
        lastFilteredTilt = filteredTilt
        currentPosition = (sweepPhase - 0.5) * (maxPosition * 2.0)
    }
    
    private func updateVerticalTilt(withRaw rawVTilt: Double) {
        if centerVerticalTilt == nil {
            centerVerticalTilt = rawVTilt
        }
        guard let centerVerticalTilt else { return }
        let relativeVTilt = rawVTilt - centerVerticalTilt
        filteredVerticalTilt = filteredVerticalTilt + (relativeVTilt - filteredVerticalTilt) * baseTiltSmoothing
        verticalTiltPosition = filteredVerticalTilt
        if let lastFilteredVerticalTilt {
            let rawVelocity = filteredVerticalTilt - lastFilteredVerticalTilt
            filteredVerticalTiltVelocity = filteredVerticalTiltVelocity + (rawVelocity - filteredVerticalTiltVelocity) * phaseVelocitySmoothing
        } else {
            filteredVerticalTiltVelocity = 0.0
        }
        verticalTiltVelocity = filteredVerticalTiltVelocity
        self.lastFilteredVerticalTilt = filteredVerticalTilt
    }

    private func checkStillness(userAcceleration: CMAcceleration) {
        let magnitude = sqrt(
            userAcceleration.x * userAcceleration.x +
            userAcceleration.y * userAcceleration.y +
            userAcceleration.z * userAcceleration.z
        )
        filteredSpeed = filteredSpeed + (magnitude - filteredSpeed) * speedSmoothing
        motionSpeed = min(1.0, max(0.0, filteredSpeed / maxSpeedForNormalization))
        
        if magnitude < stillnessThreshold {
            if lastStillTime == nil {
                lastStillTime = Date()
            } else if let stillTime = lastStillTime,
                      Date().timeIntervalSince(stillTime) >= stillnessDuration {
                if !isStill {
                    DispatchQueue.main.async {
                        self.isStill = true
                    }
                }
            }
        } else {
            lastStillTime = nil
            if isStill {
                DispatchQueue.main.async {
                    self.isStill = false
                }
            }
        }
    }
    
    func resetPosition(to position: Double) {
        currentPosition = position
    }

    /// Called by the display view each frame to capture what's actually on screen
    func updateDisplayState(tiltNorm: Double, textX: Double, textY: Double, arcDrop: Double, opacity: Double) {
        displayTiltNorm = tiltNorm
        displayTextX = textX
        displayTextY = textY
        displayArcDrop = arcDrop
        displayOpacity = opacity
    }

    // MARK: - Recording

    func startRecording() {
        recordedSamples.removeAll()
        recordingStartTime = CACurrentMediaTime()
        isRecording = true
        print("🔴 RECORDING STARTED")
    }

    func stopRecording() {
        isRecording = false
        print("⏹️ RECORDING STOPPED — \(recordedSamples.count) samples captured")
    }

    private func recordSample(motion: CMDeviceMotion) {
        guard let startTime = recordingStartTime else { return }
        let t = CACurrentMediaTime() - startTime
        let sample = MotionSample(
            timestamp: t,
            gravityX: motion.gravity.x,
            gravityY: motion.gravity.y,
            gravityZ: motion.gravity.z,
            userAccelX: motion.userAcceleration.x,
            userAccelY: motion.userAcceleration.y,
            userAccelZ: motion.userAcceleration.z,
            roll: motion.attitude.roll,
            pitch: motion.attitude.pitch,
            yaw: motion.attitude.yaw,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            rawTilt: lastRawTilt,
            relativeTilt: lastRelativeTilt,
            filteredTilt: filteredTilt,
            filteredTiltVelocity: filteredTiltVelocity,
            sweepPhase: sweepPhase,
            currentPosition: currentPosition,
            motionSpeed: motionSpeed,
            displayTiltNorm: displayTiltNorm,
            displayTextX: displayTextX,
            displayTextY: displayTextY,
            displayArcDrop: displayArcDrop,
            displayOpacity: displayOpacity
        )
        recordedSamples.append(sample)
    }

    /// Saves CSV to the app's documents directory and returns the file URL for sharing
    func exportRecording() -> URL? {
        let header = "time,grav_x,grav_y,grav_z,accel_x,accel_y,accel_z,roll,pitch,yaw,gyro_x,gyro_y,gyro_z,raw_tilt,rel_tilt,filt_tilt,filt_tilt_vel,sweep_phase,position,speed,disp_tilt_norm,disp_text_x,disp_text_y,disp_arc_drop,disp_opacity"
        var lines = [header]
        for s in recordedSamples {
            let row = String(format: "%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%.4f,%.4f,%.6f,%.4f,%.1f,%.4f,%.4f,%.1f,%.1f,%.1f,%.3f",
                s.timestamp,
                s.gravityX, s.gravityY, s.gravityZ,
                s.userAccelX, s.userAccelY, s.userAccelZ,
                s.roll, s.pitch, s.yaw,
                s.rotationRateX, s.rotationRateY, s.rotationRateZ,
                s.rawTilt, s.relativeTilt, s.filteredTilt,
                s.filteredTiltVelocity,
                s.sweepPhase, s.currentPosition, s.motionSpeed,
                s.displayTiltNorm, s.displayTextX, s.displayTextY,
                s.displayArcDrop, s.displayOpacity)
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")

        // Build a timestamped filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: Date())
        let filename = "showt_motion_\(stamp).csv"

        // Write to app's Documents directory (accessible via Files app if enabled)
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not access Documents directory")
            return nil
        }
        let fileURL = docs.appendingPathComponent(filename)

        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to write CSV: \(error)")
            return nil
        }

        // Print summary to console (still useful when Xcode IS connected)
        if !recordedSamples.isEmpty {
            let duration = recordedSamples.last!.timestamp
            let fps = Double(recordedSamples.count) / max(duration, 0.001)
            let phases = recordedSamples.map { $0.sweepPhase }
            let tilts = recordedSamples.map { $0.relativeTilt }
            let speeds = recordedSamples.map { $0.motionSpeed }
            let dTiltNorms = recordedSamples.map { $0.displayTiltNorm }
            let dTextXs = recordedSamples.map { $0.displayTextX }
            let dArcDrops = recordedSamples.map { $0.displayArcDrop }

            print("\n📊 ═══════════════════════════════════════")
            print("   MOTION RECORDING SUMMARY")
            print("   ═══════════════════════════════════════")
            print("   Duration:     \(String(format: "%.2f", duration))s")
            print("   Samples:      \(recordedSamples.count)")
            print("   Avg FPS:      \(String(format: "%.1f", fps))")
            print("   ───────────────────────────────────────")
            print("   Tilt range:   \(String(format: "%.4f", tilts.min()!)) → \(String(format: "%.4f", tilts.max()!))")
            print("   Phase range:  \(String(format: "%.4f", phases.min()!)) → \(String(format: "%.4f", phases.max()!))")
            print("   Speed range:  \(String(format: "%.4f", speeds.min()!)) → \(String(format: "%.4f", speeds.max()!))")
            print("   ─── Display State ─────────────────────")
            print("   TiltNorm:     \(String(format: "%.4f", dTiltNorms.min()!)) → \(String(format: "%.4f", dTiltNorms.max()!))")
            print("   TextX:        \(String(format: "%.1f", dTextXs.min()!)) → \(String(format: "%.1f", dTextXs.max()!))")
            print("   ArcDrop:      \(String(format: "%.1f", dArcDrops.min()!)) → \(String(format: "%.1f", dArcDrops.max()!))")
            print("   Saved to:     \(fileURL.path)")
            print("   ═══════════════════════════════════════\n")
        }

        return fileURL
    }

    deinit {
        stopMotionUpdates()
    }

    private func startAccelerometerFallback() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self = self, let data = data else { return }
            self.updatePosition(withTilt: data.acceleration.x)
            self.updateVerticalTilt(withRaw: 0.0)
            self.checkStillness(userAcceleration: CMAcceleration(
                x: data.acceleration.x,
                y: data.acceleration.y,
                z: data.acceleration.z
            ))
        }
    }
    
    #if targetEnvironment(simulator)
    private func startMockMotion() {
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            self.mockTime += 1.0/60.0
            let waveSpeed = 0.8
            let stillnessCycle = fmod(self.mockTime, 8.0)
            let mockTilt: Double
            if stillnessCycle > 6.0 {
                mockTilt = 0.0
            } else {
                mockTilt = sin(self.mockTime * waveSpeed * 2 * .pi) * 0.35
            }
            
            self.updatePosition(withTilt: mockTilt)
            let mockVTilt = sin(self.mockTime * 0.3 * 2 * .pi) * 0.15
            self.updateVerticalTilt(withRaw: mockVTilt)

            let motionMagnitude = abs(cos(self.mockTime * waveSpeed * 2 * .pi)) * 0.03
            let mockUserAcceleration = CMAcceleration(
                x: stillnessCycle > 6.0 ? 0.0 : motionMagnitude,
                y: 0.0,
                z: 0.0
            )
            
            self.checkStillness(userAcceleration: mockUserAcceleration)
        }
    }
    #endif
}
