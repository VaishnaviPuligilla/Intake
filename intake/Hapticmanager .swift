// HapticManager.swift
// Manages haptic feedback generation across the application.
// Supports CoreHaptics hardware-level feedback when available.
// Falls back to UIKit vibration feedback if hardware haptics are unsupported.
// Designed as a singleton for centralized feedback control.
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// Singleton manager responsible for handling user tactile feedback.
// Provides lightweight, medium, and strong feedback patterns.
// Optimized for offline-safe execution and hardware capability detection.
final class HapticManager {
    static let shared = HapticManager()
    private init() { prepareEngine() }

    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            engine?.playsHapticsOnly = true
            try engine?.start()
            engine?.stoppedHandler = { [weak self] _ in
                try? self?.engine?.start()
            }
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
        } catch {
            engine = nil
        }
    }

    private func play(intensity: Float, sharpness: Float) {
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            uiFeedback(intensity: intensity)
            return
        }
        let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
        let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player  = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }
    #else
    private func prepareEngine() {}
    private func play(intensity: Float, sharpness: Float) {
        uiFeedback(intensity: intensity)
    }
    #endif

    private func uiFeedback(intensity: Float) {
        #if canImport(UIKit)
        if intensity < 0.4 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if intensity < 0.7 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        #endif
    }

    func light()   { play(intensity: 0.35, sharpness: 0.50) }
    func medium()  { play(intensity: 0.55, sharpness: 0.60) }
    func heavy()   { play(intensity: 0.80, sharpness: 0.70) }

    func success() {
        play(intensity: 0.50, sharpness: 0.80)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    func warning() {
        play(intensity: 0.65, sharpness: 0.65)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    func error() {
        play(intensity: 0.90, sharpness: 0.40)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}
