import SwiftUI
import UIKit

// GAP mode: one letter at a time, full-screen, flashed only when that letter's
// virtual column is centred under the phone. Screen is black between letters,
// creating a true strobe / POV effect with no slit persistence.

struct GapView: View {
    let text: String
    @Binding var showDisplayView: Bool
    @StateObject private var motionManager = MotionManager()
    @State private var previousBrightness: CGFloat = 0.5
    @State private var letterImages: [UIImage] = []
    @State private var textSegments: [String] = []
    @State private var activeSegmentIndex: Int = 0
    @State private var lastSweepEdge: Int? = nil

    // Same tilt geometry as slit mode — letters anchor at fixed tilt angles.
    private let tiltHalfRange: CGFloat = 0.65
    private let minLookaheadFrames: CGFloat = 0.8
    private let maxLookaheadFrames: CGFloat = 4.0
    private let velocityForMaxLookahead: CGFloat = 0.02
    private let maxCharsPerSegment: Int = 6

    // Duty cycle: fraction of each letter's column where the screen lights up.
    // 0.45 means the letter is on for the middle 45% of its virtual zone;
    // the surrounding 55% is black (the "gap").
    private let flashFraction: CGFloat = 0.45

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                guard !letterImages.isEmpty else { return }

                // Speed-adaptive lookahead — identical to slit mode.
                let speed = CGFloat(motionManager.motionSpeed)
                let tilt = CGFloat(motionManager.tiltPosition)
                let tiltVelocity = CGFloat(motionManager.tiltVelocity)
                let velocityNorm = min(1.0, abs(tiltVelocity) / velocityForMaxLookahead)
                let lookaheadMix = min(1.0, (speed * 0.6) + (velocityNorm * 0.4))
                let lookaheadFrames = minLookaheadFrames + (maxLookaheadFrames - minLookaheadFrames) * lookaheadMix
                let predictedTilt = max(-tiltHalfRange, min(tiltHalfRange, tilt + tiltVelocity * lookaheadFrames))
                let tiltNorm = (predictedTilt + tiltHalfRange) / (2 * tiltHalfRange)

                // Map tiltNorm [0,1] onto letter columns.
                let n = letterImages.count
                let currentFloat = tiltNorm * CGFloat(n)
                let letterIndex = max(0, min(n - 1, Int(currentFloat)))
                let letterFraction = currentFloat - CGFloat(letterIndex) // 0..1 within the column

                // 0 = phone is at the centre of this letter's column, 1 = at the edge.
                let distFromCenter = abs(letterFraction - 0.5) * 2.0

                // Black between letters — only draw when inside the flash window.
                guard distFromCenter < flashFraction else { return }

                let image = letterImages[letterIndex]

                // Scale to fit within the screen, preserving aspect ratio.
                // Using both height and width targets handles wide glyphs (W, M).
                let targetH = size.height * 0.85
                let targetW = size.width  * 0.95
                let scale   = min(targetH / image.size.height, targetW / image.size.width)
                let displayW = image.size.width  * scale
                let displayH = image.size.height * scale

                let destRect = CGRect(
                    x: (size.width  - displayW) / 2,
                    y: (size.height - displayH) / 2,
                    width:  displayW,
                    height: displayH
                )
                context.draw(Image(uiImage: image), in: destRect)
            }

            VStack {
                HStack {
                    Button(action: { showDisplayView = false }) {
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
            configureLetterImages()
        }
        .onReceive(motionManager.$sweepPhase) { phase in
            handleSweepEdge(phase: phase)
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            motionManager.stopMotionUpdates()
        }
    }

    // MARK: - Segment management

    private func configureLetterImages() {
        textSegments = splitTextForSweep(text, maxChars: maxCharsPerSegment)
        if textSegments.isEmpty { textSegments = [text] }
        activeSegmentIndex = 0
        lastSweepEdge = nil
        generateLetterImages(for: textSegments[activeSegmentIndex])
    }

    private func handleSweepEdge(phase: Double) {
        guard textSegments.count > 1 else { return }
        let leftEdgeThreshold  = 0.02
        let rightEdgeThreshold = 0.98
        let resetLow  = 0.10
        let resetHigh = 0.90

        if phase <= leftEdgeThreshold {
            if lastSweepEdge != -1 { lastSweepEdge = -1; advanceToNextSegment() }
        } else if phase >= rightEdgeThreshold {
            if lastSweepEdge != 1  { lastSweepEdge =  1; advanceToNextSegment() }
        } else if phase > resetLow && phase < resetHigh {
            lastSweepEdge = nil
        }
    }

    private func advanceToNextSegment() {
        guard !textSegments.isEmpty else { return }
        activeSegmentIndex = (activeSegmentIndex + 1) % textSegments.count
        generateLetterImages(for: textSegments[activeSegmentIndex])
    }

    // Copied verbatim from DisplayView so both views stay self-contained.
    private func splitTextForSweep(_ source: String, maxChars: Int) -> [String] {
        let normalized = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if normalized.isEmpty { return [] }

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
                if !current.isEmpty { result.append(current); current = "" }
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
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Image generation

    private func generateLetterImages(for chunk: String) {
        // One full-screen image per character; spaces are skipped.
        let characters = chunk.filter { !$0.isWhitespace }
        let fontSize: CGFloat = 800
        let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        letterImages = characters.map { char in
            let charStr = String(char) as NSString
            let measured = charStr.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude,
                             height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).integral
            let textSize = CGSize(width: max(1, measured.width), height: max(1, measured.height))

            // scale=2.0 for crisp rendering when each letter is near screen size
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2.0
            let renderer = UIGraphicsImageRenderer(size: textSize, format: format)
            return renderer.image { ctx in
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: textSize))
                charStr.draw(at: CGPoint(x: -measured.minX, y: -measured.minY),
                             withAttributes: attributes)
            }
        }
    }
}

struct GapView_Previews: PreviewProvider {
    static var previews: some View {
        GapView(text: "HELLO", showDisplayView: .constant(true))
    }
}
