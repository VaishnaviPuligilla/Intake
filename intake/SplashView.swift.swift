// Splash screen with animated clock, greeting typing effect, and exit transition.
import SwiftUI
import Combine

// Determines time-based greeting and tagline display.
enum TimePeriod {
    case morning
    case afternoon
    case evening

    static var current: TimePeriod {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 3..<12:  return .morning
        case 12..<17: return .afternoon
        default:      return .evening
        }
    }

    var greeting: String {
        switch self {
        case .morning:   return "Good Morning"
        case .afternoon: return "Good Afternoon"
        case .evening:   return "Good Evening"
        }
    }

    var tagline: String { "Stay mindful of what you eat" }
}

// Main splash screen view with animation pipeline.
struct SplashView: View {
    let onFinished: () -> Void

    private let period = TimePeriod.current

    
    @State private var now: Date = Date()
    
    private let ticker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    @State private var clockScale: CGFloat  = 0.3
    @State private var clockOpacity: Double = 0
    @State private var greetingText          = ""
    @State private var taglineText           = ""
    @State private var textOpacity: Double   = 0
    @State private var exitOpacity: Double   = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image("intake_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer().frame(height: geo.size.height * 0.10)

                    SplashClockView(date: now, size: min(geo.size.width * 0.52, 210))
                        .scaleEffect(clockScale)
                        .opacity(clockOpacity)

                    Spacer().frame(height: 44)

                    Text(greetingText)
                        .font(.system(size: 20, weight: .thin, design: .serif))
                        .foregroundColor(.white)
                        .opacity(textOpacity)
                        .tracking(4.0)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                    Spacer().frame(height: 14)

                    Text(taglineText)
                        .font(.system(size: 14, weight: .thin, design: .serif))
                        .foregroundColor(.white.opacity(0.75))
                        .opacity(textOpacity)
                        .tracking(2.5)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .opacity(exitOpacity)
        }
        .ignoresSafeArea()
        .onAppear { runAnimation() }

        .onReceive(ticker) { date in
            now = date
        }
    }

    private func runAnimation() {
        withAnimation(.spring(response: 0.80, dampingFraction: 0.62).delay(0.5)) {
            clockScale   = 1.0
            clockOpacity = 1.0
        }
        withAnimation(.easeIn(duration: 0.6).delay(1.6)) {
            textOpacity = 1.0
        }
        typeLetters(period.greeting, into: $greetingText, startDelay: 1.8, speed: 0.07)
        typeWords(period.tagline,    into: $taglineText,  startDelay: 3.5, wordDelay: 0.20)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.6) {
            withAnimation(.easeIn(duration: 1.4)) { exitOpacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { onFinished() }
    }

    private func typeLetters(_ text: String, into binding: Binding<String>,
                              startDelay: Double, speed: Double) {
        for (i, ch) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + Double(i) * speed) {
                binding.wrappedValue.append(ch)
            }
        }
    }

    private func typeWords(_ text: String, into binding: Binding<String>,
                            startDelay: Double, wordDelay: Double) {
        let words = text.split(separator: " ").map(String.init)
        for (i, word) in words.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + Double(i) * wordDelay) {
                let cur = binding.wrappedValue
                binding.wrappedValue = cur.isEmpty ? word : cur + " " + word
            }
        }
    }
}

// Analog clock rendering component for splash animation.
struct SplashClockView: View {

    let date: Date
    let size: CGFloat

    @State private var intakeLabel  = ""
    @State private var labelOpacity: Double = 0

    private let cal = Calendar.current

    var body: some View {
        ZStack {
            
            Circle()
                .fill(Color.white)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6)

            Circle()
                .strokeBorder(Color.black.opacity(0.04), lineWidth: size * 0.005)
                .frame(width: size * 0.92, height: size * 0.92)

            ForEach([0, 90, 180, 270], id: \.self) { deg in
                tickMark(atDegrees: Double(deg), major: true)
            }

            ForEach([30, 60, 120, 150, 210, 240, 300, 330], id: \.self) { deg in
                tickMark(atDegrees: Double(deg), major: false)
            }

            handPath(angle: hourAngle, length: size * 0.25, tail: size * 0.05)
                .stroke(Color.black.opacity(0.82),
                        style: StrokeStyle(lineWidth: size * 0.034, lineCap: .round))

            handPath(angle: minuteAngle, length: size * 0.33, tail: size * 0.06)
                .stroke(Color.black.opacity(0.78),
                        style: StrokeStyle(lineWidth: size * 0.023, lineCap: .round))

            handPath(angle: secondAngle, length: size * 0.37, tail: size * 0.08)
                .stroke(Color(red: 0.15, green: 0.60, blue: 0.28).opacity(0.90),
                        style: StrokeStyle(lineWidth: size * 0.011, lineCap: .round))

            Circle()
                .fill(Color.black.opacity(0.80))
                .frame(width: size * 0.046, height: size * 0.046)

            Circle()
                .fill(Color(red: 0.15, green: 0.60, blue: 0.28).opacity(0.90))
                .frame(width: size * 0.030, height: size * 0.030)

            Text(intakeLabel)
                .font(.system(size: size * 0.118, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(Color(red: 0.02, green: 0.07, blue: 0.03).opacity(0.90))
                .tracking(size * 0.016)
                .opacity(labelOpacity)
                .offset(y: -(size * 0.148))
        }
        .frame(width: size, height: size)
        .onAppear { typeIntakeLabel() }
    }

    private func typeIntakeLabel() {
        withAnimation(.easeIn(duration: 0.4).delay(0.8)) { labelOpacity = 1.0 }
        for (i, ch) in "Intake".enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + Double(i) * 0.10) {
                intakeLabel.append(ch)
            }
        }
    }

    private func tickMark(atDegrees deg: Double, major: Bool) -> some View {
        let rad    = CGFloat(deg * .pi / 180.0)
        let half   = size / 2
        let outer  = size * 0.44
        let inner  = outer - (major ? size * 0.065 : size * 0.038)
        let path   = Path { p in
            p.move(to: CGPoint(x: half + sin(rad) * inner, y: half - cos(rad) * inner))
            p.addLine(to: CGPoint(x: half + sin(rad) * outer, y: half - cos(rad) * outer))
        }
        return path
            .stroke(Color.black.opacity(major ? 0.28 : 0.12),
                    style: StrokeStyle(lineWidth: major ? size * 0.022 : size * 0.012,
                                       lineCap: .round))
            .frame(width: size, height: size)
    }

    private func handPath(angle: Double, length: CGFloat, tail: CGFloat) -> Path {
        Path { p in
            p.move(to:    CGPoint(x: size/2 - sin(angle) * tail,   y: size/2 + cos(angle) * tail))
            p.addLine(to: CGPoint(x: size/2 + sin(angle) * length, y: size/2 - cos(angle) * length))
        }
    }

    private var secondAngle: Double {
        let s  = Double(cal.component(.second,     from: date))
        let ns = Double(cal.component(.nanosecond, from: date)) / 1_000_000_000
        return (s + ns) / 60.0 * 2 * .pi
    }

    private var minuteAngle: Double {
        let m = Double(cal.component(.minute, from: date))
        let s = Double(cal.component(.second, from: date))
        return (m + s / 60.0) / 60.0 * 2 * .pi
    }

    private var hourAngle: Double {
        let h = Double(cal.component(.hour, from: date)).truncatingRemainder(dividingBy: 12)
        let m = Double(cal.component(.minute, from: date))
        return (h + m / 60.0) / 12.0 * 2 * .pi
    }
}

#Preview {
    SplashView(onFinished: {})
}
