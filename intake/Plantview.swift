// PlantView visualizes product expiry lifecycle using animated plant metaphors.
// State meaning mapping:
//
// fresh → Expiry remaining more than 3 days (Green plant)
// drying → Expiry remaining is 3, 2, or 1 day (Yellow warning plant)
// dead → Product already expired (Brown / dead plant)
// blooming → User consumed product before expiry (Reward positive state)

import SwiftUI

private struct FallingLeaf: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
    var speed: Double
    var drift: CGFloat
}

private struct FloatingPetal: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var opacity: Double
    var riseSpeed: Double
}

struct PlantView: View {
    let state: PlantState
    var size: CGFloat = 200

    @State private var sway      = false
    @State private var floating  = false

    @State private var leaves: [FallingLeaf] = []
    @State private var leafTimer: Timer?

    @State private var petals: [FloatingPetal] = []
    @State private var petalTimer: Timer?

    @State private var glowPulse = false

    var body: some View {
        ZStack {
            if state == .blooming {
                Circle()
                    .fill(Color.green.opacity(glowPulse ? 0.18 : 0.06))
                    .frame(width: size * 0.80, height: size * 0.80)
                    .blur(radius: 16)
                    .animation(
                        .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: glowPulse
                    )
            }

            ForEach(leaves) { leaf in
                Text("🍂")
                    .font(.system(size: size * 0.12 * leaf.scale))
                    .position(x: leaf.x, y: leaf.y)
                    .rotationEffect(.degrees(leaf.rotation))
                    .opacity(leaf.opacity)
            }

            Image(state.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .blendMode(.multiply)
                .saturation(1.08)
                .contrast(1.08)
                .rotationEffect(
                    swayAngle,
                    anchor: .bottom
                )
                .offset(y: state == .dead ? 0 : (floating ? -7 : 0))
                .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 4)
                .animation(swayAnimation, value: sway)
                .animation(floatAnimation, value: floating)

            ForEach(petals) { petal in
                Text("✿")
                    .font(.system(size: size * 0.10 * petal.scale))
                    .foregroundColor(Color.pink.opacity(0.75))
                    .position(x: petal.x, y: petal.y)
                    .rotationEffect(.degrees(petal.rotation))
                    .opacity(petal.opacity)
            }
        }
        .frame(width: size, height: size)
        .onAppear { startAnimations() }
        .onDisappear { stopTimers() }
        .onChange(of: state) { _, _ in
            stopTimers()
            leaves  = []
            petals  = []
            sway    = false
            floating = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                startAnimations()
            }
        }
    }
    private var swayAngle: Angle {
        switch state {
        case .fresh:    return .degrees(sway ? 5.0  : -5.0)
        case .drying:   return .degrees(sway ? 3.2  : -3.2)
        case .dead:     return .degrees(0)
        case .blooming: return .degrees(sway ? 6.0  : -6.0)
        }
    }

    private var swayAnimation: Animation? {
        switch state {
        case .fresh:    return .easeInOut(duration: 3.2).repeatForever(autoreverses: true)
        case .drying:   return .easeInOut(duration: 4.6).repeatForever(autoreverses: true)
        case .dead:     return nil
        case .blooming: return .easeInOut(duration: 2.8).repeatForever(autoreverses: true)
        }
    }

    private var floatAnimation: Animation? {
        switch state {
        case .fresh:    return .easeInOut(duration: 2.8).repeatForever(autoreverses: true)
        case .drying:   return .easeInOut(duration: 4.0).repeatForever(autoreverses: true)
        case .dead:     return nil
        case .blooming: return .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
        }
    }
    private func startAnimations() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sway     = true
            floating = true
        }

        if state == .dead {
            startFallingLeaves()
        } else if state == .blooming {
            glowPulse = true
            startFloatingPetals()
        }
    }

    private func stopTimers() {
        leafTimer?.invalidate()
        leafTimer = nil
        petalTimer?.invalidate()
        petalTimer = nil
        glowPulse = false
    }
    private func startFallingLeaves() {
        spawnLeaf()
        leafTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { _ in
            spawnLeaf()
            animateLeaves()
        }
    }

    private func spawnLeaf() {
        let leaf = FallingLeaf(
            x: CGFloat.random(in: size * 0.15 ... size * 0.85),
            y: size * 0.25,
            rotation: Double.random(in: 0 ... 360),
            scale: CGFloat.random(in: 0.6 ... 1.2),
            opacity: 0.0,
            speed: Double.random(in: 2.5 ... 4.5),
            drift: CGFloat.random(in: -10 ... 10)
        )
        leaves.append(leaf)
        if leaves.count > 8 { leaves.removeFirst() }
    }

    private func animateLeaves() {
        for i in leaves.indices {
            withAnimation(.easeIn(duration: leaves[i].speed)) {
                leaves[i].y       += size * 0.70
                leaves[i].rotation += Double.random(in: 80 ... 200)
                leaves[i].x       += leaves[i].drift * 3
                leaves[i].opacity  = i < leaves.count - 1 ? 0.0 : 0.85
            }
        }
    }

    private func startFloatingPetals() {
        spawnPetal()
        petalTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { _ in
            spawnPetal()
            animatePetals()
        }
    }

    private func spawnPetal() {
        let petal = FloatingPetal(
            x: CGFloat.random(in: size * 0.20 ... size * 0.80),
            y: size * 0.75,
            rotation: Double.random(in: 0 ... 360),
            scale: CGFloat.random(in: 0.5 ... 1.1),
            opacity: 0.0,
            riseSpeed: Double.random(in: 2.0 ... 3.5)
        )
        petals.append(petal)
        if petals.count > 7 { petals.removeFirst() }
    }

    private func animatePetals() {
        for i in petals.indices {
            withAnimation(.easeOut(duration: petals[i].riseSpeed)) {
                petals[i].y        -= size * 0.55
                petals[i].rotation += Double.random(in: 60 ... 180)
                petals[i].x       += CGFloat.random(in: -12 ... 12)
                petals[i].opacity  = i < petals.count - 1 ? 0.0 : 0.80
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach([PlantState.fresh, .drying, .dead, .blooming], id: \.rawValue) { s in
            PlantView(state: s, size: 80)
        }
    }
    .padding()
    .background(Color(red: 0.04, green: 0.10, blue: 0.06))
}
