import SwiftUI

struct SplashView: View {
    @State private var compassRotation: Double = -30
    @State private var compassScale: CGFloat = 0.6
    @State private var compassOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.3
    @State private var ringOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var tickOpacity: Double = 0

    var body: some View {
        ZStack {
            // Navy background with subtle texture
            Color.brandDarkNavy.ignoresSafeArea()

            // Radial glow behind compass
            RadialGradient(
                colors: [Color.brandGold.opacity(glowOpacity * 0.15), .clear],
                center: .center,
                startRadius: 50,
                endRadius: 250
            )

            VStack(spacing: 0) {
                Spacer()

                // Compass rose
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(Color.brandGold.opacity(ringOpacity * 0.3), lineWidth: 2)
                        .frame(width: 220, height: 220)
                        .scaleEffect(ringScale)

                    // Tick marks ring
                    ForEach(0..<36, id: \.self) { i in
                        Rectangle()
                            .fill(Color.brandGold.opacity(i % 9 == 0 ? 0.5 : 0.2))
                            .frame(width: i % 9 == 0 ? 2 : 1, height: i % 9 == 0 ? 12 : 6)
                            .offset(y: -95)
                            .rotationEffect(.degrees(Double(i) * 10))
                            .opacity(tickOpacity)
                    }

                    // Green cardinal points
                    ForEach([0, 90, 180, 270], id: \.self) { angle in
                        CompassPointShape()
                            .fill(Color.brandGreen)
                            .frame(width: 30, height: 75)
                            .offset(y: -45)
                            .rotationEffect(.degrees(Double(angle)))
                    }

                    // Gold intercardinal points
                    ForEach([45, 135, 225, 315], id: \.self) { angle in
                        CompassPointShape()
                            .fill(Color.brandGold)
                            .frame(width: 16, height: 60)
                            .offset(y: -38)
                            .rotationEffect(.degrees(Double(angle)))
                    }

                    // Center
                    Circle()
                        .fill(Color.brandGold)
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(Color.brandDarkNavy)
                        .frame(width: 26, height: 26)
                    Text("W")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.brandGold)
                }
                .rotationEffect(.degrees(compassRotation))
                .scaleEffect(compassScale)
                .opacity(compassOpacity)

                Spacer().frame(height: 40)

                // App name
                VStack(spacing: 6) {
                    Text("wAIpoint")
                        .font(.system(size: 36, weight: .bold, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.brandGold, Color(red: 0.85, green: 0.73, blue: 0.45)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)

                    Text("Your AI Tour Guide")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.4))
                        .opacity(subtitleOpacity)
                }

                Spacer()

                // Bottom branding
                Text("Explore the world, one waypoint at a time")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(subtitleOpacity * 0.3))
                    .padding(.bottom, 40)
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        // Phase 1: Compass fades in and rotates
        withAnimation(.easeOut(duration: 0.8)) {
            compassOpacity = 1
            compassScale = 1.0
            compassRotation = 0
        }

        // Phase 2: Ring expands
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringScale = 1.0
            ringOpacity = 1
        }

        // Phase 3: Tick marks appear
        withAnimation(.easeIn(duration: 0.4).delay(0.5)) {
            tickOpacity = 1
        }

        // Phase 4: Glow
        withAnimation(.easeInOut(duration: 0.8).delay(0.6)) {
            glowOpacity = 1
        }

        // Phase 5: Title slides up
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.8)) {
            titleOpacity = 1
            titleOffset = 0
        }

        // Phase 6: Subtitle
        withAnimation(.easeIn(duration: 0.5).delay(1.2)) {
            subtitleOpacity = 1
        }
    }
}

// Compass point triangle shape
struct CompassPointShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
