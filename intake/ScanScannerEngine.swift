// Camera OCR subsystem for real-time expiry date detection.
// Responsibilities:
// - Capture live camera frames
// - Perform Vision-based text recognition
// - Extract expiry date patterns from OCR lines
// - Normalize OCR noise and correct common character misreads
// - Validate detected expiry dates before callback

import SwiftUI
import AVFoundation
import Vision
import Combine

enum CameraError: Error, Equatable {
    case permissionDenied, unavailable, unknown
    var title: String {
        switch self {
        case .permissionDenied: return "Camera Access Needed"
        case .unavailable:      return "Camera Unavailable"
        case .unknown:          return "Something went wrong"
        }
    }
    var message: String {
        switch self {
        case .permissionDenied: return "Please allow camera access in Settings → Privacy → Camera."
        case .unavailable:      return "No camera could be found on this device."
        case .unknown:          return "An unexpected error occurred."
        }
    }
    var icon: String {
        switch self {
        case .permissionDenied: return "camera.fill.badge.ellipsis"
        case .unavailable:      return "camera.slash.fill"
        case .unknown:          return "exclamationmark.triangle.fill"
        }
    }
}

// Manages camera session lifecycle and real-time OCR inference pipeline.
// Uses Vision framework for lightweight on-device text detection.
final class CameraController: NSObject, ObservableObject,
                               AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var session: AVCaptureSession?

    var onLowLight:       ((Bool) -> Void)?
    var onError:          ((CameraError) -> Void)?
    var onExpiryDetected: ((Date) -> Void)?

    private var lightTimer:   Timer?
    private var device:       AVCaptureDevice?
    private var lastScanTime: Date = .distantPast
    private var didDetect     = false
    private var wantsRunning  = false

    private let visionQueue  = DispatchQueue(label: "intake.vision",  qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "intake.session", qos: .userInitiated)

    func start() {
        wantsRunning = true
        didDetect    = false
        checkPermission()
    }

    func stop() {
        wantsRunning = false
        lightTimer?.invalidate()
        lightTimer = nil
        let s = session
        sessionQueue.async { s?.stopRunning() }
        DispatchQueue.main.async { self.session = nil }
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.wantsRunning else { return }
                    granted ? self.setupSession() : self.onError?(.permissionDenied)
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async { self.onError?(.permissionDenied) }
        @unknown default:
            DispatchQueue.main.async { self.onError?(.unknown) }
        }
    }

    private func setupSession() {
        guard wantsRunning else { return }

        guard let dev = findCamera() else {
            DispatchQueue.main.async { self.onError?(.unavailable) }
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: dev) else {
            DispatchQueue.main.async { self.onError?(.unavailable) }
            return
        }
        device = dev

        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        guard newSession.canAddInput(input) else {
            newSession.commitConfiguration()
            DispatchQueue.main.async { self.onError?(.unavailable) }
            return
        }
        newSession.addInput(input)
        newSession.sessionPreset = newSession.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: visionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if newSession.canAddOutput(output) { newSession.addOutput(output) }
        newSession.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsRunning else { return }
            self.session = newSession          // preview attaches; session is now non-nil

            self.sessionQueue.async { [weak self] in
                guard let self, self.wantsRunning else { return }
                newSession.startRunning()      // frames begin — session already set above

                #if os(iOS)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.wantsRunning else { return }
                    self.lightTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                        guard let dev = self?.device else { return }
                        DispatchQueue.main.async { self?.onLowLight?(dev.isLowLightBoostEnabled) }
                    }
                }
                #endif
            }
        }
    }

    private func findCamera() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        #if os(macOS)
        if #available(macOS 14.0, *) { types.append(.external) }
        else { types.append(.externalUnknown) }
        #endif
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices
        #if os(macOS)
        let filtered = devices.filter {
            let n = $0.localizedName.lowercased()
            return !n.contains("continuity") && !n.contains("desk view") && !n.contains("iphone")
        }
        return (filtered.isEmpty ? devices : filtered).first
        #else
        return devices.first(where: { $0.position == .back })
            ?? devices.first(where: { $0.position == .front })
            ?? devices.first
        #endif
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard !didDetect,
              session != nil,
              now.timeIntervalSince(lastScanTime) > 0.3,
              let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastScanTime = now

        let req = VNRecognizeTextRequest { [weak self] r, _ in
            guard let self, !self.didDetect else { return }
            let lines = (r.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            if let date = self.findExpiryDate(inLines: lines) {
                self.didDetect = true
                DispatchQueue.main.async { self.onExpiryDetected?(date) }
            }
        }
        req.recognitionLevel       = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages   = ["en-US", "en-GB"]
        req.minimumTextHeight      = 0.002
        try? VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req])
    }

    // Core expiry detection logic.
    // Strategy:
    // 1. Filter manufacturing-related text
    // 2. Prioritize expiry keyword context
    // 3. Normalize OCR corruption artifacts
    // 4. Parse multiple international date formats
    // 5. Validate date plausibility range
    private func findExpiryDate(inLines lines: [String]) -> Date? {
        let mfgKeywords = ["mfg","mfd","manufactured","manufacture","dom",
                           "date of manufacture","production","packed","pack date","packaged","lot","batch"]
        let expiryKeywords = ["exp","expiry","expiration","use by","use before",
                              "best before","best by","bb","best if used by",
                              "sell by","enjoy by","consume by","bbe","expires"]

        func isMfg(_ t: String) -> Bool    { let l = t.lowercased(); return mfgKeywords.contains    { l.contains($0) } }
        func isExpiry(_ t: String) -> Bool { let l = t.lowercased(); return expiryKeywords.contains { l.hasPrefix($0) || l.contains($0) } }

        let normalized = lines.map(normalizeOCRForDate)

        for (i, line) in normalized.enumerated() {
            guard !isMfg(line), isExpiry(line) else { continue }
            if let d = extractDate(from: line) { return d }
            if i + 1 < normalized.count {
                let next = normalized[i + 1]
                if !isMfg(next), let d = extractDate(from: next) { return d }
            }
            if let d = extractDateAddingYear(from: line), isValidExpiry(d) { return d }
        }

        for line in normalized {
            guard !isMfg(line) else { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count <= 18, let d = extractDate(from: t) { return d }
        }

        for line in normalized {
            guard !isMfg(line) else { continue }
            if let d = extractDate(from: line) { return d }
        }

        let joined = normalized.joined(separator: " ")
        if let d = extractDate(from: joined) { return d }
        if let d = extractDateAddingYear(from: joined), isValidExpiry(d) { return d }

        return nil
    }

    private func normalizeOCRForDate(_ text: String) -> String {
        let tokens = text.uppercased().split(whereSeparator: \.isWhitespace)
        return tokens.map { rawToken in
            var token = String(rawToken)
            let hasNumericContext = token.contains { $0.isNumber || "-/.".contains($0) }
            guard hasNumericContext else { return token }
            token = token.replacingOccurrences(of: "O", with: "0")
            token = token.replacingOccurrences(of: "I", with: "1")
            token = token.replacingOccurrences(of: "L", with: "1")
            token = token.replacingOccurrences(of: "S", with: "5")
            token = token.replacingOccurrences(of: "B", with: "8")
            return token
        }
        .joined(separator: " ")
    }

    private func extractDate(from text: String) -> Date? {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
        let lowerOriginal = text.lowercased()
        let hasExpiryCue = [
            "exp", "expiry", "expires", "use by", "use before",
            "best before", "best by", "bbe", "consume by", "sell by"
        ].contains { lowerOriginal.contains($0) }
        let cleaned = text
            .replacingOccurrences(of: "EXP",         with: "")
            .replacingOccurrences(of: "EXPIRES",      with: "")
            .replacingOccurrences(of: "BEST BEFORE",  with: "")
            .replacingOccurrences(of: "USE BY",       with: "")
            .replacingOccurrences(of: "USE BEFORE",   with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns: [(String, [String])] = [
            (#"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})"#,     ["dd/MM/yyyy","dd-MM-yyyy","dd.MM.yyyy","MM/dd/yyyy","MM-dd-yyyy"]),
            (#"(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2})(?!\d)"#,["dd/MM/yy","dd-MM-yy","MM/dd/yy","MM-dd-yy"]),
            (#"(\d{4})[/\-\.](\d{1,2})[/\-\.](\d{1,2})"#,      ["yyyy-MM-dd","yyyy/MM/dd","yyyy.MM.dd"]),
            (#"(\d{1,2})[/\-\.](\d{4})"#,                       ["MM/yyyy","MM-yyyy","MM.yyyy"]),
            (#"([A-Za-z]{3,9})[\s\-\.]+(\d{4})"#,               ["MMM yyyy","MMMMyyyy","MMMM yyyy"]),
            (#"(\d{1,2})[\s\-\.]+([A-Za-z]{3,9})[\s\-\.]+(\d{4})"#, ["dd MMM yyyy","dd MMMM yyyy","d MMM yyyy"]),
            (#"([A-Za-z]{3,9})[\s\-\.]+(\d{1,2})[\s,\-\.]+(\d{4})"#, ["MMMM d yyyy","MMM d yyyy","MMMM dd yyyy","MMM dd yyyy"]),
            (#"(\d{4})[\s\-\.]+([A-Za-z]{3,9})[\s\-\.]+(\d{1,2})"#, ["yyyy MMM d","yyyy MMM dd","yyyy MMMM d","yyyy MMMM dd"]),
            (#"(\d{4})[\s\-\.]+([A-Za-z]{3,9})"#,               ["yyyy MMM","yyyy MMMM"]),
            (#"(\d{1,2})[\s\-\.]+([A-Za-z]{3,9})(?![\s,\-\.]+\d)"#, ["dd MMM","d MMM","dd MMMM","d MMMM"]),
            (#"([A-Za-z]{3,9})[\s\-\.]+(\d{1,2})(?![\s,\-\.]+\d)"#, ["MMM d","MMMM d","MMM dd","MMMM dd"]),
            (#"(\d{1,2})[/\-\.](\d{2})(?!\d)"#,                 ["MM/yy","MM-yy","MM.yy"]),
            (#"\b(\d{8})\b"#,                                    ["yyyyMMdd"]),
            (#"\b(\d{6})\b"#,                                    ["ddMMyy","MMddyy","yyMMdd"]),
        ]

        for (pattern, formats) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = NSRange(cleaned.startIndex..., in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, range: ns),
                  let r = Range(match.range, in: cleaned) else { continue }
            let matched = String(cleaned[r]).trimmingCharacters(in: .whitespaces)

            if formats.contains("MM/yy") {
                let parts = matched.components(separatedBy: CharacterSet(charactersIn: "-/."))
                if parts.count == 2, let yy = Int(parts[1]) {
                    let currentYY = Calendar.current.component(.year, from: Date()) % 100
                    if yy < currentYY - 1 || yy > currentYY + 10 { continue }
                }
            }

            for fmt in formats {
                df.dateFormat = fmt
                if let d = df.date(from: matched) {
                    let resolved = resolveDayMonthWithoutYearIfNeeded(baseDate: d, format: fmt)
                    let monthResolved = resolveMonthOnlyDateIfNeeded(baseDate: resolved, format: fmt)
                    return monthResolved
                }
            }
        }

        if hasExpiryCue,
           let dayOnlyRegex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?!\d)\b"#) {
            let ns = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = dayOnlyRegex.firstMatch(in: cleaned, range: ns),
               let dayRange = Range(match.range(at: 1), in: cleaned),
               let day = Int(cleaned[dayRange]), (1...31).contains(day) {
                let cal = Calendar.current
                let now = Date()
                var comps = cal.dateComponents([.year, .month], from: now)
                if let dayRangeInMonth = cal.range(of: .day, in: .month, for: now) {
                    comps.day = min(day, dayRangeInMonth.upperBound - 1)
                } else {
                    comps.day = day
                }
                if let resolved = cal.date(from: comps) {
                    return resolved
                }
            }
        }

        if let yearOnlyRegex = try? NSRegularExpression(pattern: #"\b(20\d{2})\b"#) {
            let ns = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = yearOnlyRegex.firstMatch(in: cleaned, range: ns),
               let yearRange = Range(match.range(at: 1), in: cleaned),
               let year = Int(cleaned[yearRange]) {
                var comps = DateComponents()
                comps.year = year
                comps.month = 12
                comps.day = 31
                if let endOfYear = Calendar.current.date(from: comps) {
                    return endOfYear
                }
            }
        }
        return nil
    }

    private func resolveMonthOnlyDateIfNeeded(baseDate: Date, format: String) -> Date {
        let monthOnlyFormats: Set<String> = [
            "MM/yyyy","MM-yyyy","MM.yyyy",
            "MMM yyyy","MMMMyyyy","MMMM yyyy",
            "yyyy MMM","yyyy MMMM",
            "MM/yy","MM-yy","MM.yy"
        ]
        guard monthOnlyFormats.contains(format) else { return baseDate }
        if let interval = Calendar.current.dateInterval(of: .month, for: baseDate) {
            return Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? baseDate
        }
        return baseDate
    }

    private func resolveDayMonthWithoutYearIfNeeded(baseDate: Date, format: String) -> Date {
        let dayMonthFormats: Set<String> = [
            "dd MMM","d MMM","dd MMMM","d MMMM",
            "MMM d","MMMM d","MMM dd","MMMM dd"
        ]
        guard dayMonthFormats.contains(format) else { return baseDate }
        let cal = Calendar.current
        let dayMonth = cal.dateComponents([.month, .day], from: baseDate)
        let currentYear = cal.component(.year, from: Date())
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = dayMonth.month
        comps.day = dayMonth.day
        return cal.date(from: comps) ?? baseDate
    }

    private func extractDateAddingYear(from text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})[/\-\.](\d{1,2})(?![/\-\.]\d)"#) else { return nil }
        let ns = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: ns),
              let r = Range(match.range, in: text) else { return nil }
        let parts = String(text[r]).components(separatedBy: CharacterSet(charactersIn: "-/."))
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "dd/MM/yyyy"
        for (d, m) in [(a, b), (b, a)] {
            guard m >= 1 && m <= 12 && d >= 1 && d <= 31 else { continue }
            for y in [year, year + 1] {
                let str = String(format: "%02d/%02d/%04d", d, m, y)
                if let date = df.date(from: str), isValidExpiry(date) { return date }
            }
        }
        return nil
    }

    private func isValidExpiry(_ date: Date) -> Bool {
        let now    = Date()
        let past   = Calendar.current.date(byAdding: .month, value: -6, to: now)!
        let future = Calendar.current.date(byAdding: .year,  value: 12, to: now)!
        return date >= past && date <= future
    }
}

#if canImport(UIKit)
import UIKit

final class CameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    func attachSession(_ newSession: AVCaptureSession) {
        guard previewLayer?.session !== newSession else { return }
        previewLayer?.removeFromSuperlayer()
        let pl = AVCaptureVideoPreviewLayer(session: newSession)
        pl.videoGravity = .resizeAspectFill
        pl.frame = bounds
        layer.insertSublayer(pl, at: 0)
        previewLayer = pl
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var controller: CameraController
    func makeUIView(context: Context) -> CameraPreviewUIView { CameraPreviewUIView() }
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if let session = controller.session { uiView.attachSession(session) }
    }
}

#elseif os(macOS)
import AppKit

final class CameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func attachSession(_ newSession: AVCaptureSession) {
        guard previewLayer?.session !== newSession else { return }
        previewLayer?.removeFromSuperlayer()
        let pl = AVCaptureVideoPreviewLayer(session: newSession)
        pl.videoGravity = .resizeAspectFill
        pl.frame = bounds
        layer?.insertSublayer(pl, at: 0)
        previewLayer = pl
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreviewRepresentable: NSViewRepresentable {
    @ObservedObject var controller: CameraController
    func makeNSView(context: Context) -> CameraPreviewNSView { CameraPreviewNSView() }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        if let session = controller.session { nsView.attachSession(session) }
    }
}
#endif
