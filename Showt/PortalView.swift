import SwiftUI
import UIKit

struct PortalView: View {
    let text: String
    @Binding var showDisplayView: Bool
    @StateObject private var motionManager = MotionManager()
    @State private var previousBrightness: CGFloat = 0.5
    @State private var textImage: UIImage?

    // Tilt ranges — narrower than slit mode since portal is slow deliberate pan, not a fast wave.
    // gravity.z ranges ±sin(angle): ±0.40 covers roughly ±24° of forward/backward tilt.
    // gravity.x ranges ±sin(angle): ±0.40 covers roughly ±24° of left/right tilt.
    private let tiltHalfRange: CGFloat = 0.40
    private let verticalTiltHalfRange: CGFloat = 0.40

    // Speed-adaptive lookahead (same constants as DisplayView)
    private let minLookaheadFrames: CGFloat = 0.8
    private let maxLookaheadFrames: CGFloat = 4.0
    private let velocityForMaxLookahead: CGFloat = 0.02

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                guard let image = textImage else { return }

                let speed = CGFloat(motionManager.motionSpeed)
                let tilt = CGFloat(motionManager.tiltPosition)
                let tiltVelocity = CGFloat(motionManager.tiltVelocity)
                let vTilt = CGFloat(motionManager.verticalTiltPosition)
                let vTiltVelocity = CGFloat(motionManager.verticalTiltVelocity)

                // Speed-adaptive lookahead
                let velocityNorm = min(1.0, abs(tiltVelocity) / velocityForMaxLookahead)
                let lookaheadMix = min(1.0, (speed * 0.6) + (velocityNorm * 0.4))
                let lookaheadFrames = minLookaheadFrames + (maxLookaheadFrames - minLookaheadFrames) * lookaheadMix

                let predictedTilt = max(-tiltHalfRange, min(tiltHalfRange, tilt + tiltVelocity * lookaheadFrames))
                let predictedVTilt = max(-verticalTiltHalfRange, min(verticalTiltHalfRange, vTilt + vTiltVelocity * lookaheadFrames))

                // Normalize to [0..1]: 0 = left/up, 1 = right/down
                let tiltNorm = (predictedTilt + tiltHalfRange) / (2 * tiltHalfRange)
                let vTiltNorm = (predictedVTilt + verticalTiltHalfRange) / (2 * verticalTiltHalfRange)

                // Scale text to fit within the screen height (80%).
                // Letters are readable at rest; panning reveals blank canvas around them.
                let targetH = size.height * 0.80
                let scale = targetH / image.size.height
                let scaledW = image.size.width * scale
                let scaledH = targetH

                // Virtual canvas margins: the amount of blank space around the text that
                // the user can pan into. Using screen dimensions means a full tilt-range
                // sweep moves the sign completely off-screen in that direction.
                let canvasMarginX = max(size.width, (scaledW + size.width) / 2)
                let canvasMarginY = size.height

                // At center tilt (norm=0.5) the sign is centered on screen.
                // Tilting right → sign scrolls left (revealing its right side).
                // Tilting down  → sign scrolls up  (revealing its lower side / exits top).
                let centeredX = (size.width  - scaledW) / 2
                let centeredY = (size.height - scaledH) / 2
                let imageX = centeredX - (tiltNorm  - 0.5) * 2 * canvasMarginX
                let imageY = centeredY - (vTiltNorm - 0.5) * 2 * canvasMarginY

                let destRect = CGRect(x: imageX, y: imageY, width: scaledW, height: scaledH)
                context.draw(Image(uiImage: image), in: destRect)

                // Vignette overlay: radial gradient, clear in center → dark at edges
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let fullRadius = sqrt(pow(size.width / 2, 2) + pow(size.height / 2, 2))
                let innerRadius = fullRadius * 0.45
                let gradient = Gradient(colors: [.clear, Color.black.opacity(0.65)])
                let vignetteShading = GraphicsContext.Shading.radialGradient(
                    gradient,
                    center: center,
                    startRadius: innerRadius,
                    endRadius: fullRadius
                )
                context.fill(Path(CGRect(origin: .zero, size: size)), with: vignetteShading)
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
                }
                .padding(.top, 50)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            motionManager.startMotionUpdates()
            generateTextImage()
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            motionManager.stopMotionUpdates()
        }
    }

    private func generateTextImage() {
        let charCount = max(1, text.count)
        let fontSize: CGFloat
        switch charCount {
        case ...3:
            fontSize = 960
        case 4...6:
            fontSize = 820
        case 7...9:
            fontSize = 700
        case 10...12:
            fontSize = 620
        case 13...16:
            fontSize = 540
        default:
            fontSize = 460
        }

        let kernFactor: CGFloat
        switch charCount {
        case ...4:
            kernFactor = 0.10
        case 5...7:
            kernFactor = 0.07
        default:
            kernFactor = 0.045
        }

        let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: fontSize * kernFactor
        ]

        let nsText = text as NSString
        let measured = nsText.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).integral
        let textSize = CGSize(width: max(1, measured.width), height: max(1, measured.height))

        // scale = 2.0 gives enough resolution since the image is upscaled to 2.5× screen height.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: textSize, format: format)
        textImage = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: textSize))
            let drawPoint = CGPoint(x: -measured.minX, y: -measured.minY)
            nsText.draw(at: drawPoint, withAttributes: attributes)
        }
    }
}

struct PortalView_Previews: PreviewProvider {
    static var previews: some View {
        PortalView(text: "HELLO", showDisplayView: .constant(true))
    }
}
