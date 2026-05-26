import SwiftUI

/// Full-screen celebratory overlay shown when the user marks a medication as taken.
/// Features: scaling checkmark with a radial burst, animated confetti, and a "Nice!" label.
struct CelebrationView: View {
    let medicationName: String

    @State private var checkScale: CGFloat = 0.2
    @State private var checkOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.4
    @State private var ringOpacity: Double = 0.9
    @State private var labelOffset: CGFloat = 30
    @State private var labelOpacity: Double = 0
    @State private var burstProgress: CGFloat = 0

    private let burstColors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]

    var body: some View {
        ZStack {
            // Dimming background — tappable to dismiss early but doesn't block much.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .transition(.opacity)

            // Confetti burst
            ConfettiBurst()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                ZStack {
                    // Expanding ring behind the check
                    Circle()
                        .stroke(Color.green.opacity(0.8), lineWidth: 6)
                        .frame(width: 160, height: 160)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)

                    // Radial sparkle burst lines
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(burstColors[i % burstColors.count])
                            .frame(width: 6, height: 22)
                            .offset(y: -60 - (burstProgress * 40))
                            .opacity(Double(1 - burstProgress))
                            .rotationEffect(.degrees(Double(i) * 30))
                    }

                    // Filled circle with check
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                        .shadow(color: .green.opacity(0.6), radius: 24, x: 0, y: 8)
                        .scaleEffect(checkScale)
                        .opacity(checkOpacity)

                    Image(systemName: "checkmark")
                        .font(.system(size: 70, weight: .heavy))
                        .foregroundStyle(.white)
                        .scaleEffect(checkScale)
                        .opacity(checkOpacity)
                }

                VStack(spacing: 4) {
                    Text("Nice work!")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !medicationName.isEmpty {
                        Text("\(medicationName) taken")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .offset(y: labelOffset)
                .opacity(labelOpacity)
            }
        }
        .onAppear { runAnimations() }
    }

    private func runAnimations() {
        // Check pops in with a bouncy spring.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            checkScale = 1.0
            checkOpacity = 1.0
        }

        // Ring expands and fades.
        withAnimation(.easeOut(duration: 0.9)) {
            ringScale = 1.8
            ringOpacity = 0
        }

        // Radial burst lines fly outward.
        withAnimation(.easeOut(duration: 0.8)) {
            burstProgress = 1.0
        }

        // Label slides up after a beat.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.18)) {
            labelOffset = 0
            labelOpacity = 1
        }
    }
}

// MARK: - ConfettiBurst

private struct ConfettiBurst: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<60, id: \.self) { i in
                    ConfettiPiece(index: i, screenSize: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let screenSize: CGSize

    @State private var progress: CGFloat = 0
    @State private var rotation: Double = 0

    // Per-piece random properties, fixed at init so they survive re-renders.
    private let angle: Double
    private let distance: CGFloat
    private let size: CGFloat
    private let color: Color
    private let fallExtra: CGFloat
    private let duration: Double
    private let rotationEnd: Double

    private static let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .blue, .purple, .pink, .cyan]

    init(index: Int, screenSize: CGSize) {
        self.index = index
        self.screenSize = screenSize
        // Spread base angle evenly around the circle, then jitter.
        let baseAngle = Double(index) / 60.0 * 360.0
        self.angle = baseAngle + Double.random(in: -12...12)
        self.distance = CGFloat.random(in: 180...360)
        self.size = CGFloat.random(in: 6...12)
        self.color = Self.colors[index % Self.colors.count]
        self.fallExtra = CGFloat.random(in: 120...260)
        self.duration = Double.random(in: 1.4...2.0)
        self.rotationEnd = Double.random(in: 360...1080) * (index.isMultiple(of: 2) ? 1 : -1)
    }

    var body: some View {
        let startX = screenSize.width / 2
        let startY = screenSize.height / 2 - 20
        let radians = angle * .pi / 180
        // Burst outward, then gravity pulls pieces down.
        let outX = cos(radians) * distance * progress
        let outY = sin(radians) * distance * progress
        let gravityY = fallExtra * progress * progress

        Rectangle()
            .fill(color)
            .frame(width: size, height: size * 0.5)
            .rotationEffect(.degrees(rotation))
            .position(x: startX + outX, y: startY + outY + gravityY)
            .opacity(Double(1 - progress * 0.7))
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    progress = 1
                }
                withAnimation(.linear(duration: duration)) {
                    rotation = rotationEnd
                }
            }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        CelebrationView(medicationName: "Aspirin")
    }
}
