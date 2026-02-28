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

    // Multi-slit barrier parameters
    private let slitCount: Int = 40
    private let slitWidth: CGFloat = 4
    // Tilt range mapped to full text scroll.
    // ±0.65 rad covers the actual swing range (data shows ±0.78 at fast extremes).
    private let tiltHalfRange: CGFloat = 0.65

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                guard let image = textImage else { return }

                let imageW = image.size.width
                let imageH = image.size.height

                // Scale text so letters fill ~70% of screen height
                let displayH = size.height * 0.70
                let scaleFactor = displayH / imageH
                let displayW = imageW * scaleFactor

                // Tilt controls horizontal scroll of the text behind the barrier.
                // tiltPosition negative = phone tilted left → show left part of text
                // tiltPosition positive = phone tilted right → show right part of text
                let tilt = CGFloat(motionManager.tiltPosition)
                let tiltNorm = max(0, min(1, (tilt + tiltHalfRange) / (2 * tiltHalfRange)))

                // Scroll margin adds black space at the arc extremes
                let scrollMargin = size.width * 0.25
                let maxScroll = max(0, displayW - size.width) + scrollMargin * 2
                let textX = scrollMargin - tiltNorm * maxScroll

                // Fixed vertical position — the phone's physical arc already
                // provides vertical displacement; adding screen-space offset
                // would double the motion and hurt legibility.
                let arcDrop: CGFloat = 0
                let textY = (size.height - displayH) / 2

                // Build barrier mask — evenly spaced vertical slits across the screen
                let spacing = size.width / CGFloat(slitCount)
                var mask = Path()
                for i in 0..<slitCount {
                    let x = CGFloat(i) * spacing
                    mask.addRect(CGRect(x: x, y: 0, width: slitWidth, height: size.height))
                }

                // Clip to the slit mask, then draw the full text image at the
                // tilt-driven offset. Only the portions behind slits are visible.
                let speed = CGFloat(motionManager.motionSpeed)
                let opacity: CGFloat
                if strobeEnabled {
                    let pulse = (sin(CACurrentMediaTime() * 56) + 1) * 0.5
                    let gate = speed > 0.12 ? (pulse > 0.52 ? 1.0 : 0.15) : 0.1
                    opacity = max(0.15, (0.5 + speed * 0.5) * gate)
                } else {
                    // Dim when still, bright when moving
                    opacity = max(0.35, 0.5 + speed * 0.5)
                }

                // Report display state for recording
                motionManager.updateDisplayState(
                    tiltNorm: Double(tiltNorm),
                    textX: Double(textX),
                    textY: Double(textY),
                    arcDrop: Double(arcDrop),
                    opacity: Double(opacity)
                )

                var maskedContext = context
                maskedContext.clip(to: mask)
                maskedContext.opacity = opacity
                let destRect = CGRect(x: textX, y: textY, width: displayW, height: displayH)
                maskedContext.draw(Image(uiImage: image), in: destRect)
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

            generateTextImage()
            motionManager.resetPosition(to: 0.0)
            motionManager.startMotionUpdates()
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            motionManager.stopMotionUpdates()
        }
    }
    
    private func generateTextImage() {
        // Create much larger text so letters nearly fill the screen
        let fontSize: CGFloat = 800  // Doubled from 400 for bigger letters
        let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        
        // Add spacing for wider letters
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: fontSize * 0.1  // Reduced spacing since letters are bigger
        ]
        
        let textSize = text.size(withAttributes: attributes)
        
        // Store text width for calculations
        textWidth = textSize.width
        
        // Reset phone position to center of virtual world
        motionManager.resetPosition(to: 0.0)
        
        // Create simple text image - no extensions, no padding
        let renderer = UIGraphicsImageRenderer(size: textSize)
        textImage = renderer.image { context in
            // Black background
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: textSize))
            
            // White text
            text.draw(at: CGPoint.zero, withAttributes: attributes)
        }
        
        // DEBUG: Print simple info
        print("📐 STATIONARY SIGN CREATED:")
        print("   Text: '\(text)'")
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

#Preview {
    DisplayView(text: "HELLO", showDisplayView: .constant(true))
}
