import SwiftUI
import UIKit
import QuartzCore

struct DisplayView: View {
    let text: String
    @Binding var showDisplayView: Bool
    @StateObject private var motionManager = MotionManager()
    @State private var previousBrightness: CGFloat = 0.5
    @State private var textImage: UIImage?
    @State private var textWidth: CGFloat = 0
    @State private var strobeEnabled: Bool = false
    @State private var exportedFileURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var textSegments: [String] = []
    @State private var activeSegmentIndex: Int = 0
    @State private var lastSweepEdge: Int? = nil

    // Multi-slit barrier parameters
    private let slitCount: Int = 40
    // Narrower slits reduce visual permanence/blur during fast sweeps.
    private let slitWidth: CGFloat = 2.6
    private let minimumSlitWidth: CGFloat = 1.0
    // Tilt range mapped to full text scroll.
    // ±0.65 rad covers the actual swing range (data shows ±0.78 at fast extremes).
    private let tiltHalfRange: CGFloat = 0.65
    // Speed-adaptive timing compensation for fast sweeps.
    private let minLookaheadFrames: CGFloat = 0.8
    private let maxLookaheadFrames: CGFloat = 4.0
    private let velocityForMaxLookahead: CGFloat = 0.02
    // Global vertical arc added at sweep extremes (matches recorded motion profile).
    private let sweepArcMaxDrop: CGFloat = 80
    private let sweepArcPower: CGFloat = 2.0
    // Per-column baseline curvature so letters form an arch instead of a flat line.
    private let letterArcMaxDrop: CGFloat = 28
    private let letterArcPower: CGFloat = 2.0
    // Target larger apparent letter height on screen.
    private let textHeightFraction: CGFloat = 0.90
    // Keep each segment short enough to remain readable within one sweep.
    private let maxCharsPerSegment: Int = 6

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                guard let image = textImage else { return }

                let imageW = image.size.width
                let imageH = image.size.height

                // Scale text so letters fill most of the visible area.
                let displayH = size.height * textHeightFraction
                let scaleFactor = displayH / imageH
                let displayW = imageW * scaleFactor

                // Tilt controls horizontal scroll of the text behind the barrier.
                // tiltPosition negative = phone tilted left → show left part of text
                // tiltPosition positive = phone tilted right → show right part of text
                let speed = CGFloat(motionManager.motionSpeed)
                let tilt = CGFloat(motionManager.tiltPosition)
                let tiltVelocity = CGFloat(motionManager.tiltVelocity)
                let velocityNorm = min(1.0, abs(tiltVelocity) / velocityForMaxLookahead)
                let lookaheadMix = min(1.0, (speed * 0.6) + (velocityNorm * 0.4))
                let lookaheadFrames = minLookaheadFrames + (maxLookaheadFrames - minLookaheadFrames) * lookaheadMix
                let predictedTilt = max(-tiltHalfRange, min(tiltHalfRange, tilt + tiltVelocity * lookaheadFrames))
                let tiltNorm = max(0, min(1, (predictedTilt + tiltHalfRange) / (2 * tiltHalfRange)))

                // Scroll margin adds black space at the arc extremes
                let scrollMargin = size.width * 0.25
                let maxScroll = max(0, displayW - size.width) + scrollMargin * 2
                let textX = scrollMargin - tiltNorm * maxScroll

                // Arc offsets only move content downward, so bias upward to keep
                // the larger letters visually centered while preserving headroom.
                let baseTextY = (size.height - displayH) / 2 - (sweepArcMaxDrop * 0.35 + letterArcMaxDrop * 0.35)
                let centeredTilt = abs(tiltNorm - 0.5) * 2.0
                let arcDrop = pow(centeredTilt, sweepArcPower) * sweepArcMaxDrop

                // Slit spacing for the multi-slit barrier effect
                let spacing = size.width / CGFloat(slitCount)
                let effectiveSlitWidth = max(minimumSlitWidth, slitWidth - speed * 1.8)

                // Clip to the slit mask, then draw the full text image at the
                // tilt-driven offset. Only the portions behind slits are visible.
                let opacity: CGFloat
                if strobeEnabled {
                    let pulse = (sin(CACurrentMediaTime() * 56) + 1) * 0.5
                    let gate = speed > 0.12 ? (pulse > 0.52 ? 1.0 : 0.15) : 0.1
                    opacity = max(0.15, (0.5 + speed * 0.5) * gate)
                } else {
                    // Reduce persistence in the measured fast-swing regime (speed ~0.95..1.0).
                    let highSpeedFactor = max(0, min(1, (speed - 0.80) / 0.20))
                    let highSpeedAttenuation = 1.0 - (0.24 * highSpeedFactor)
                    opacity = max(0.40, (0.55 + speed * 0.45) * highSpeedAttenuation)
                }

                // Report display state for recording
                motionManager.updateDisplayState(
                    tiltNorm: Double(tiltNorm),
                    textX: Double(textX),
                    textY: Double(baseTextY + arcDrop),
                    arcDrop: Double(arcDrop),
                    opacity: Double(opacity)
                )

                // Draw each slit independently so we can apply a horizontal arch
                // to the text baseline and keep characters readable during sweeps.
                for i in 0..<slitCount {
                    let x = CGFloat(i) * spacing
                    let slitRect = CGRect(x: x, y: 0, width: effectiveSlitWidth, height: size.height)
                    let slitCenterNorm = ((x + (effectiveSlitWidth * 0.5)) / size.width - 0.5) * 2.0
                    let localArc = pow(abs(slitCenterNorm), letterArcPower) * letterArcMaxDrop

                    var slitContext = context
                    slitContext.clip(to: Path(slitRect))
                    slitContext.opacity = opacity
                    let destRect = CGRect(
                        x: textX,
                        y: baseTextY + arcDrop + localArc,
                        width: displayW,
                        height: displayH
                    )
                    slitContext.draw(Image(uiImage: image), in: destRect)
                }
            }

            VStack {
                HStack {
                    Button(action: {
                        showDisplayView = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Button(action: {
                        strobeEnabled.toggle()
                    }) {
                        Text(strobeEnabled ? "STROBE" : "SOLID")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal, 20)

                Spacer()

                // Recording controls — always visible at bottom
                HStack(spacing: 16) {
                    if motionManager.isRecording {
                        // Pulsing red dot + STOP
                        Button(action: {
                            motionManager.stopRecording()
                        }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                Text("STOP")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.3))
                            .clipShape(Capsule())
                        }

                        Text("\(motionManager.recordedSamples.count)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red)
                    } else {
                        // REC button
                        Button(action: {
                            motionManager.startRecording()
                        }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                Text("REC")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                        }

                        // EXPORT button (only if there are samples)
                        if !motionManager.recordedSamples.isEmpty {
                            Button(action: {
                                exportedFileURL = motionManager.exportRecording()
                                if exportedFileURL != nil {
                                    showShareSheet = true
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14))
                                    Text("EXPORT \(motionManager.recordedSamples.count)")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.bottom, 50)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0

            motionManager.resetPosition(to: 0.0)
            motionManager.startMotionUpdates()
            configureSegmentsAndGenerate()
        }
        .onReceive(motionManager.$sweepPhase) { phase in
            handleSweepEdge(phase: phase)
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            motionManager.stopMotionUpdates()
        }
    }

    private func configureSegmentsAndGenerate() {
        textSegments = splitTextForSweep(text, maxChars: maxCharsPerSegment)
        if textSegments.isEmpty {
            textSegments = [text]
        }
        activeSegmentIndex = 0
        lastSweepEdge = nil
        generateTextImage(for: textSegments[activeSegmentIndex])
    }

    private func handleSweepEdge(phase: Double) {
        guard textSegments.count > 1 else { return }

        let leftEdgeThreshold = 0.02
        let rightEdgeThreshold = 0.98
        let resetLow = 0.10
        let resetHigh = 0.90

        if phase <= leftEdgeThreshold {
            if lastSweepEdge != -1 {
                lastSweepEdge = -1
                advanceToNextSegment()
            }
        } else if phase >= rightEdgeThreshold {
            if lastSweepEdge != 1 {
                lastSweepEdge = 1
                advanceToNextSegment()
            }
        } else if phase > resetLow && phase < resetHigh {
            lastSweepEdge = nil
        }
    }

    private func advanceToNextSegment() {
        guard !textSegments.isEmpty else { return }
        activeSegmentIndex = (activeSegmentIndex + 1) % textSegments.count
        generateTextImage(for: textSegments[activeSegmentIndex])
    }

    private func splitTextForSweep(_ source: String, maxChars: Int) -> [String] {
        let normalized = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if normalized.isEmpty {
            return []
        }

        func splitLongWord(_ word: String) -> [String] {
            var parts: [String] = []
            var start = word.startIndex
            while start < word.endIndex {
                let end = word.index(start, offsetBy: maxChars, limitedBy: word.endIndex) ?? word.endIndex
                parts.append(String(word[start..<end]))
                start = end
            }
            return parts
        }

        var result: [String] = []
        var current = ""

        for rawWord in normalized.split(separator: " ") {
            let word = String(rawWord)
            if word.count > maxChars {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                result.append(contentsOf: splitLongWord(word))
                continue
            }

            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= maxChars {
                current += " " + word
            } else {
                result.append(current)
                current = word
            }
        }

        if !current.isEmpty {
            result.append(current)
        }

        return result
    }

    private func generateTextImage(for textChunk: String) {
        // Create large text and render using a tight glyph bounding box so
        // the drawn letters occupy more of the destination rect vertically.
        let chunkLength = max(1, textChunk.count)
        let fontSize: CGFloat
        switch chunkLength {
        case ...4:
            fontSize = 920
        case 5...7:
            fontSize = 860
        case 8...10:
            fontSize = 780
        default:
            fontSize = 700
        }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .black)

        // Reduce character spacing for longer segments to preserve readability.
        let kernFactor: CGFloat
        switch chunkLength {
        case ...4:
            kernFactor = 0.10
        case 5...7:
            kernFactor = 0.07
        default:
            kernFactor = 0.045
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: fontSize * kernFactor
        ]

        let nsText = textChunk as NSString
        let measured = nsText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral
        let textSize = CGSize(width: max(1, measured.width), height: max(1, measured.height))

        // Store text width for calculations
        textWidth = textSize.width
        
        // Reset phone position to center of virtual world
        motionManager.resetPosition(to: 0.0)
        
        // Render tightly cropped glyphs to avoid extra top/bottom padding.
        let renderer = UIGraphicsImageRenderer(size: textSize)
        textImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: textSize))

            let drawPoint = CGPoint(x: -measured.minX, y: -measured.minY)
            nsText.draw(at: drawPoint, withAttributes: attributes)
        }
        
        // DEBUG: Print simple info
        print("📐 STATIONARY SIGN CREATED:")
        print("   Text: '\(textChunk)'")
        print("   Size: \(textSize.width) x \(textSize.height)")
    }
}

// UIKit share sheet wrapper for exporting CSV
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DisplayView_Previews: PreviewProvider {
    static var previews: some View {
        DisplayView(text: "HELLO", showDisplayView: .constant(true))
    }
}
