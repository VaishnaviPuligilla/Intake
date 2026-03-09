// CameraOCRView.swift
// Handles real-time camera OCR scanning for ingredient and expiry detection.
// Uses Apple Vision framework for on-device text recognition.
// Designed for privacy-first offline processing.
import SwiftUI
import AVFoundation
import Vision
// This module uses AVFoundation for camera capture
// and Vision framework for optical character recognition.
let ingredientNotFoundToken = "__INGREDIENT_NOT_FOUND__"
private func correctedIngredientOCRWord(_ word: String) -> String {
    let map: [String: String] = [
        "suriflower": "sunflower",
        "sunfiower": "sunflower",
        "suniower": "sunflower",
        "vetable": "vegetable",
        "vegtable": "vegetable",
        "vegetablle": "vegetable",
        "vegeteble": "vegetable",
        "canoia": "canola"
    ]
    return map[word] ?? word
}
#if canImport(UIKit)
import UIKit
// SwiftUI wrapper bridging UIKit/macOS camera OCR controller.
struct CameraOCRView: UIViewControllerRepresentable {
    enum Mode { case expiryDate; case ingredients }
    let mode: Mode
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> CameraOCRViewController {
        CameraOCRViewController(mode: mode, onScanned: onScanned)
    }
    func updateUIViewController(_ vc: CameraOCRViewController, context: Context) {}
}
// Core camera OCR controller managing:
// - Camera lifecycle
// - Overlay UI rendering
// - Frame processing queue
// - Text recognition pipeline
final class CameraOCRViewController: UIViewController,
                                      AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Mode { case expiryDate; case ingredients }

    private let mode:      Mode
    private let onScanned: (String) -> Void

    private var captureSession:  AVCaptureSession?
    private var previewLayer:    AVCaptureVideoPreviewLayer?
    private let ocrQueue     = DispatchQueue(label: "intake.ocr",         qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "intake.ocr.session", qos: .userInitiated)
    private var shouldRunSession     = false
    private var isConfiguringSession = false
    private var cameraIsLive         = false
    private var hasScanned       = false
    private var accumulatedLines = [String]()
    private var frameCount       = 0
    private let maxFrames        = 20
    private var lastOCRTime: Date = .distantPast
    private let ingredientScanTimeout: TimeInterval = 15
    private var ingredientScanStartedAt: Date?
    private var overlayBuilt      = false
    private var dimLayer:         CAShapeLayer?
    private var borderLayer:      CAShapeLayer?
    private var scanLineLayer:    CALayer?
    private var cornerTickLayers: [CAShapeLayer] = []
    private let instructionLabel = UILabel()
    private let statusLabel      = UILabel()
    private let progressView     = UIProgressView(progressViewStyle: .bar)
    private let cancelButton     = UIButton(type: .system)
    private let torchButton      = UIButton(type: .system)
    private var isTorchOn        = false

    init(mode: Mode, onScanned: @escaping (String) -> Void) {
        self.mode      = mode
        self.onScanned = onScanned
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        styleStaticUI()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shouldRunSession = true
        resetScanState()
        #if targetEnvironment(simulator)
        showFallback(reason: .simulator)
        return
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.checkPermissionAndStart()
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        shouldRunSession = false
        cameraIsLive = false
        teardownSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if let session = captureSession { previewLayer?.session = session }
        buildOrUpdateOverlay()
    }
    private func resetScanState() {
        hasScanned       = false
        cameraIsLive     = false
        accumulatedLines = []
        frameCount       = 0
        lastOCRTime      = .distantPast
        ingredientScanStartedAt = nil
        DispatchQueue.main.async {
            self.progressView.setProgress(0, animated: false)
            self.statusLabel.text = self.mode == .ingredients
                ? "Hold steady — scanning all ingredients…"
                : "Point at the expiry date and hold steady"
        }
    }
    private func checkPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.shouldRunSession else { return }
                    granted ? self.startCamera() : self.showFallback(reason: .permissionDenied)
                }
            }
        case .denied, .restricted:
            showFallback(reason: .permissionDenied)
        @unknown default:
            showFallback(reason: .unknown)
        }
    }
    private func startCamera() {
        guard shouldRunSession else { return }
        DispatchQueue.main.async { self.cameraIsLive = false }
        guard let device = findCamera() else { showFallback(reason: .noDevice); return }
        guard let input  = try? AVCaptureDeviceInput(device: device) else { showFallback(reason: .noDevice); return }
        let session = AVCaptureSession()
        isConfiguringSession = true
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            isConfiguringSession = false
            showFallback(reason: .noDevice)
            return
        }
        session.addInput(input)
        for preset in [AVCaptureSession.Preset.hd1920x1080, .hd1280x720, .high, .medium] {
            if session.canSetSessionPreset(preset) { session.sessionPreset = preset; break }
        }
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: ocrQueue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isConfiguringSession = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewLayer?.removeFromSuperlayer()
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = self.view.bounds
            self.view.layer.insertSublayer(preview, at: 0)
            self.previewLayer   = preview
            self.captureSession = session
            self.buildOrUpdateOverlay()
            self.sessionQueue.async { [weak self] in
                guard let self, self.shouldRunSession else { return }
                session.startRunning()
                DispatchQueue.main.async {
                    guard self.shouldRunSession else { return }
                    self.cameraIsLive = true
                }
            }
        }
    }

    private func teardownSession() {
        let oldSession = captureSession
        let oldPreview = previewLayer
        captureSession = nil
        previewLayer   = nil
        safeStopSession(oldSession)
        sessionQueue.async {
            if let session = oldSession {
                if self.isConfiguringSession { return }
                session.beginConfiguration()
                session.inputs.forEach  { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                session.commitConfiguration()
            }
        }
        DispatchQueue.main.async { oldPreview?.removeFromSuperlayer() }
    }

    private func safeStopSession(_ session: AVCaptureSession?) {
        sessionQueue.async { [weak self] in
            guard let self, let session else { return }
            if self.isConfiguringSession {
                self.sessionQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.safeStopSession(session)
                }
                return
            }
            if session.isRunning { session.stopRunning() }
        }
    }

    private func findCamera() -> AVCaptureDevice? {
        let disc = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        )
        let devices  = disc.devices
        let filtered = devices.filter { d in
            let n = d.localizedName.lowercased()
            return !n.contains("continuity") && !n.contains("desk view") && !n.contains("iphone")
        }
        let candidates = filtered.isEmpty ? devices : filtered
        return candidates.first(where: { $0.position == .back })
            ?? candidates.first(where: { $0.position == .front })
            ?? candidates.first
    }
    private func scanRect(in bounds: CGRect) -> CGRect {
        let W = bounds.width
        let H = bounds.height

        switch mode {
        case .ingredients:
            let sidePad = max(min(W * 0.015, 8), 3)
            let scanW = W - sidePad * 2
            let scanH = min(max(scanW * 0.82, H * 0.62), H * 0.80)
            let scanX = (W - scanW) / 2
            let scanY = max((H - scanH) / 2 - H * 0.01, 4)
            return CGRect(x: scanX, y: scanY, width: scanW, height: scanH)
        case .expiryDate:
            let scanW = W * 0.88
            let scanH = scanW * 0.52
            let scanX = (W - scanW) / 2
            let scanY = (H - scanH) / 2 - H * 0.04
            return CGRect(x: scanX, y: scanY, width: scanW, height: scanH)
        }
    }
    private func buildOrUpdateOverlay() {
        let W = view.bounds.width
        let H = view.bounds.height
        guard W > 10, H > 10 else { return }
        let scanR = scanRect(in: view.bounds)
        if !overlayBuilt {
            let dim = CAShapeLayer()
            dim.fillRule  = .evenOdd
            dim.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
            view.layer.addSublayer(dim)
            dimLayer = dim
            let border = CAShapeLayer()
            border.strokeColor = UIColor.systemGreen.withAlphaComponent(0.90).cgColor
            border.fillColor   = UIColor.clear.cgColor
            border.lineWidth   = 2.5
            view.layer.addSublayer(border)
            borderLayer = border
            addCornerTicks(in: scanR)
            let line = CALayer()
            line.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.60).cgColor
            line.cornerRadius    = 1
            view.layer.addSublayer(line)
            scanLineLayer = line
            [instructionLabel, statusLabel, progressView, cancelButton, torchButton]
                .forEach { view.addSubview($0) }
            let closeBtn = UIButton(type: .system)
            closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            closeBtn.tintColor = UIColor.white.withAlphaComponent(0.80)
            let cfg = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
            closeBtn.setPreferredSymbolConfiguration(cfg, forImageIn: .normal)
            closeBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            closeBtn.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(closeBtn)
            NSLayoutConstraint.activate([
                closeBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
                closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                closeBtn.widthAnchor.constraint(equalToConstant: 38),
                closeBtn.heightAnchor.constraint(equalToConstant: 38),
            ])

            overlayBuilt = true
        }
        updateCornerTicks(in: scanR)
        let dimPath = UIBezierPath(rect: view.bounds)
        dimPath.append(UIBezierPath(roundedRect: scanR, cornerRadius: 14))
        dimPath.usesEvenOddFillRule = true
        dimLayer?.path    = dimPath.cgPath
        borderLayer?.path = UIBezierPath(roundedRect: scanR, cornerRadius: 14).cgPath
        let lineH: CGFloat = 2
        scanLineLayer?.frame = CGRect(x: scanR.minX + 12, y: scanR.minY,
                                       width: scanR.width - 24, height: lineH)
        scanLineLayer?.removeAnimation(forKey: "scan")
        let anim = CABasicAnimation(keyPath: "position.y")
        anim.fromValue    = scanR.minY + lineH / 2
        anim.toValue      = scanR.maxY - lineH / 2
        anim.duration     = 2.5
        anim.repeatCount  = .infinity
        anim.autoreverses = true
        scanLineLayer?.add(anim, forKey: "scan")
        let aboveY = max(scanR.minY - 44, view.safeAreaInsets.top + 8)
        let belowY = scanR.maxY + 12
        instructionLabel.frame = CGRect(x: 16, y: aboveY,      width: W - 32, height: 36)
        statusLabel.frame      = CGRect(x: 16, y: belowY,      width: W - 32, height: 20)
        progressView.frame     = CGRect(x: 32, y: belowY + 26, width: W - 64, height: 4)
        cancelButton.frame     = CGRect(x: 40, y: H - 80,      width: W - 80, height: 48)
        torchButton.frame      = CGRect(x: W - 60,
                                        y: max(aboveY - 6, view.safeAreaInsets.top + 8),
                                        width: 42, height: 42)
    }
    private func addCornerTicks(in rect: CGRect) {
        cornerTickLayers.forEach { $0.removeFromSuperlayer() }
        cornerTickLayers.removeAll()
        for _ in 0..<8 {
            let l = CAShapeLayer()
            l.strokeColor = UIColor.systemGreen.cgColor
            l.lineWidth   = 3.5
            l.fillColor   = UIColor.clear.cgColor
            l.lineCap     = .round
            view.layer.addSublayer(l)
            cornerTickLayers.append(l)
        }
        updateCornerTicks(in: rect)
    }
    private func updateCornerTicks(in rect: CGRect) {
        guard cornerTickLayers.count == 8 else { return }
        let len: CGFloat = 26
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY),   1,  1),
            (CGPoint(x: rect.maxX, y: rect.minY),  -1,  1),
            (CGPoint(x: rect.minX, y: rect.maxY),   1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY),  -1, -1),
        ]
        var idx = 0
        for (pt, dx, dy) in corners {
            let a = UIBezierPath()
            a.move(to: pt); a.addLine(to: CGPoint(x: pt.x + dx * len, y: pt.y))
            cornerTickLayers[idx].path = a.cgPath; idx += 1

            let b = UIBezierPath()
            b.move(to: pt); b.addLine(to: CGPoint(x: pt.x, y: pt.y + dy * len))
            cornerTickLayers[idx].path = b.cgPath; idx += 1
        }
    }
    private func styleStaticUI() {
        instructionLabel.text = mode == .ingredients
            ? "Point at the full ingredients list on the packaging"
            : "Point at the expiry date on the package"
        instructionLabel.textColor     = UIColor.white.withAlphaComponent(0.75)
        instructionLabel.font          = .systemFont(ofSize: 13, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2

        statusLabel.textColor     = UIColor.white.withAlphaComponent(0.55)
        statusLabel.font          = .systemFont(ofSize: 12)
        statusLabel.textAlignment = .center

        progressView.progressTintColor  = .systemGreen
        progressView.trackTintColor     = UIColor.white.withAlphaComponent(0.15)
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds      = true

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font   = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.backgroundColor    = UIColor.white.withAlphaComponent(0.14)
        cancelButton.layer.cornerRadius = 14
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.tintColor           = .white
        torchButton.backgroundColor     = UIColor.white.withAlphaComponent(0.14)
        torchButton.layer.cornerRadius  = 21
        torchButton.addTarget(self, action: #selector(toggleTorch), for: .touchUpInside)
        torchButton.isHidden            = !(findCamera()?.hasTorch ?? false)
    }
    enum FallbackReason { case simulator, permissionDenied, noDevice, unknown }

    private func showFallback(reason: FallbackReason) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.viewWithTag(98121)?.removeFromSuperview()

            var titleText = "Camera Unavailable"
            var subText   = "An unexpected error occurred."
            switch reason {
            case .simulator:        titleText = "Simulator — no camera"; subText = "Run on a real device."
            case .permissionDenied: titleText = "Camera Access Denied";  subText = "Settings → Privacy → Camera → enable Intake."
            case .noDevice:         titleText = "No Camera Found";       subText = "Could not connect to a camera."
            case .unknown: break
            }
            let stack = UIStackView()
            stack.axis = .vertical; stack.alignment = .center; stack.spacing = 16
            stack.translatesAutoresizingMaskIntoConstraints = false; stack.tag = 98121

            let icon = UIImageView(image: UIImage(systemName: "video.slash.fill"))
            icon.tintColor = UIColor.white.withAlphaComponent(0.30)
            icon.contentMode = .scaleAspectFit
            icon.widthAnchor.constraint(equalToConstant: 52).isActive  = true
            icon.heightAnchor.constraint(equalToConstant: 52).isActive = true

            let t = UILabel(); t.text = titleText
            t.textColor = UIColor.white.withAlphaComponent(0.45)
            t.font = .systemFont(ofSize: 16, weight: .medium); t.textAlignment = .center

            let s = UILabel(); s.text = subText
            s.textColor = UIColor.white.withAlphaComponent(0.28)
            s.font = .systemFont(ofSize: 13); s.textAlignment = .center; s.numberOfLines = 0

            [icon, t, s].forEach { stack.addArrangedSubview($0) }

            if reason == .permissionDenied {
                let btn = UIButton(type: .system)
                btn.setTitle("Open Settings", for: .normal)
                btn.setTitleColor(.systemGreen, for: .normal)
                btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
                btn.addTarget(self, action: #selector(self.openSettings), for: .touchUpInside)
                stack.addArrangedSubview(btn)
            }
            self.view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                stack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 40),
                stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -40),
            ])
        }
    }
    // Real-time OCR frame processing using Vision framework.
    // Maintains scan stability using frame accumulation strategy.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !hasScanned, cameraIsLive else { return }

        let now = Date()
        if mode == .ingredients {
            if ingredientScanStartedAt == nil { ingredientScanStartedAt = now }
            if let started = ingredientScanStartedAt,
               now.timeIntervalSince(started) >= ingredientScanTimeout {
                hasScanned = true
                DispatchQueue.main.async {
                    self.progressView.setProgress(0, animated: false)
                    self.statusLabel.text = "Ingredient cannot be found."
                    self.onScanned(ingredientNotFoundToken)
                }
                return
            }
        }

        guard now.timeIntervalSince(lastOCRTime) >= 0.3 else { return }
        lastOCRTime = now
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let req = VNRecognizeTextRequest { [weak self] r, _ in
            guard let self, !self.hasScanned else { return }
            let lines = (r.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            self.processIngredientLines(lines)
        }
        req.recognitionLevel       = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages   = ["en-US", "en-GB", "en-IN"]
        req.minimumTextHeight      = 0.002
        try? VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req])
    }
    //Ingredient Processing
    private func processIngredientLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        frameCount += 1

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count > 1, !accumulatedLines.contains(t) { accumulatedLines.append(t) }
        }
        guard hasIngredientKeyword(in: accumulatedLines) else {
            if frameCount >= 3 {
                DispatchQueue.main.async {
                    self.statusLabel.text = "Ingredient word isn't available to scan."
                }
            }
            if frameCount >= maxFrames {
                accumulatedLines.removeAll()
                frameCount = 0
                DispatchQueue.main.async {
                    self.progressView.setProgress(0, animated: true)
                }
            }
            return
        }

        DispatchQueue.main.async {
            self.progressView.setProgress(min(Float(self.frameCount) / Float(self.maxFrames), 0.95), animated: true)
            self.statusLabel.text = "Scanning… (\(self.frameCount)/\(self.maxFrames))"
        }

        if let block = extractIngredientBlock(fromLines: accumulatedLines), looksLikeIngredientList(block) {
            if block.count >= 35 || frameCount >= 6 || frameCount >= maxFrames {
                fireResult(block)
                return
            }
        }

        if frameCount >= maxFrames {
            accumulatedLines.removeAll()
            frameCount = 0
            DispatchQueue.main.async {
                self.progressView.setProgress(0, animated: true)
                self.statusLabel.text = "Scan near 'Ingredients' label only"
            }
        }
    }

    private func fireResult(_ text: String) {
        let cleaned = cleanedIngredientText(from: text)
        let validIngredients = validatedIngredients(from: cleaned)
        guard !validIngredients.isEmpty else {
            accumulatedLines.removeAll()
            frameCount = 0
            DispatchQueue.main.async {
                self.progressView.setProgress(0, animated: true)
                self.statusLabel.text = "Scanning… hold steady on ingredients list."
            }
            return
        }

        hasScanned = true
        DispatchQueue.main.async {
            self.progressView.setProgress(1.0, animated: true)
            self.statusLabel.text = "Captured! ✓"
            let finalText = validIngredients.joined(separator: ", ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.onScanned(finalText) }
        }
    }

    private func looksLikeIngredientList(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.count < 12 { return false }
        let blocked = ["may contain", "allergen", "allergy advice", "nutrition facts", "nutritional information"]
        if blocked.contains(where: { t.lowercased().contains($0) }) { return false }
        let parts = t
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.count >= 2
    }

    private func extractIngredientBlock(fromLines lines: [String]) -> String? {
        let keywordHints = [
            "ingredients", "ingredient", "ingrients", "ingredints",
            "ingrient", "ingrident", "ingridient", "ingredent",
            "ingredi", "ingred", "ingre", "ingri"
        ]
        let stopHints = [
            "nutrition", "nutritional", "allergen", "allergy", "may contain", "contains",
            "serving", "storage", "direction", "manufactured", "mfg", "expiry", "exp", "best before"
        ]

        var startIndex: Int?
        for (idx, line) in lines.enumerated() {
            let l = normalizeIngredientOCR(line)
            if keywordHints.contains(where: { l.contains($0) }) {
                startIndex = idx
                break
            }
        }
        guard let start = startIndex else { return nil }

        var chunks: [String] = []
        let head = stripIngredientKeyword(from: lines[start])
        if !head.isEmpty { chunks.append(head) }

        let end = min(lines.count - 1, start + 8)
        if start < end {
            for idx in (start + 1)...end {
                let line = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                let lower = line.lowercased()
                if stopHints.contains(where: { lower.contains($0) }) { break }
                chunks.append(line)
            }
        }

        var merged = chunks.joined(separator: ", ")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "|", with: ",")
            .replacingOccurrences(of: " ,", with: ",")
        if let stopRange = firstStopRange(in: merged.lowercased(), stopHints: stopHints) {
            merged = String(merged[..<stopRange.lowerBound])
        }
        return merged.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripIngredientKeyword(from line: String) -> String {
        let patterns = [
            "ingredients", "ingredient", "ingrident", "ingridient", "ingredi", "ingri", "ingred"
        ]
        let lower = line.lowercased()
        for p in patterns {
            if let r = lower.range(of: p) {
                var tail = String(line[r.upperBound...])
                while let first = tail.first, ":- .;".contains(first) {
                    tail.removeFirst()
                }
                return tail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeIngredientOCR(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "|", with: "i")
            .replacingOccurrences(of: "!", with: "i")
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "5", with: "s")
    }

    private func hasIngredientKeyword(in lines: [String]) -> Bool {
        let keywordHints = [
            "ingredients", "ingredient", "ingrients", "ingredints",
            "ingrient", "ingrident", "ingridient", "ingredent",
            "ingredi", "ingred", "ingre", "ingri"
        ]
        for line in lines {
            let normalized = normalizeIngredientOCR(line)
            if keywordHints.contains(where: { normalized.contains($0) }) { return true }
        }
        return false
    }

    private func firstStopRange(in text: String, stopHints: [String]) -> Range<String.Index>? {
        var first: Range<String.Index>?
        for hint in stopHints {
            if let r = text.range(of: hint) {
                if first == nil || r.lowerBound < first!.lowerBound { first = r }
            }
        }
        return first
    }

    private func cleanedIngredientText(from raw: String) -> String {
        let uiNoise = [
            "share", "save", "panel", "generally safe", "food ingredient",
            "ingredient analysis", "ingredients found", "nutrition facts"
        ]
        let tokens = raw
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }

        return tokens.filter { token in
            let lower = token.lowercased()
            if uiNoise.contains(where: { lower.contains($0) }) { return false }
            let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
            let digits  = token.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
            let spaces  = token.filter { $0 == " " }.count
            if letters < 1 { return false }
            if digits > 0 && digits * 3 > max(letters, 1) { return false }
            if spaces > 4 { return false }
            return true
        }.joined(separator: ", ")
    }

    private func validatedIngredients(from text: String) -> [String] {
        let rawParts = text.split(separator: ",").map { String($0) }
        let cleanedParts = rawParts
            .map { sanitizeIngredientToken($0) }
            .filter { !$0.isEmpty }
        guard !cleanedParts.isEmpty else { return [] }
        var out: [String] = []
        for token in cleanedParts {
            guard let normalized = IngredientInsightEngine.shared.normalizedOCRIngredientPhrase(token) else { continue }
            if !out.contains(normalized) { out.append(normalized) }
        }
        return Array(out.prefix(24))
    }

    private func sanitizeIngredientToken(_ token: String) -> String {
        let stopWords: Set<String> = ["and", "with", "contains", "contain", "may", "from", "per", "of", "the"]
        let units: Set<String>     = ["mg", "g", "kg", "ml", "l", "mcg", "%"]
        let normalized = token.lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        return normalized
            .split(separator: " ")
            .map(String.init)
            .map(correctedIngredientOCRWord)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .filter { !$0.allSatisfy(\.isNumber) }
            .filter { !stopWords.contains($0) && !units.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    //Actions
    @objc private func cancelTapped() { dismiss(animated: true) }
    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    @objc private func toggleTorch() {
        guard let device = findCamera(), device.hasTorch else { return }
        try? device.lockForConfiguration()
        isTorchOn.toggle()
        device.torchMode = isTorchOn ? .on : .off
        device.unlockForConfiguration()
        torchButton.setImage(
            UIImage(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"),
            for: .normal
        )
    }
}

#elseif os(macOS)
import AppKit

struct CameraOCRView: NSViewRepresentable {
    enum Mode { case expiryDate; case ingredients }
    let mode: Mode
    let onScanned: (String) -> Void

    func makeNSView(context: Context) -> MacOCRView { MacOCRView(mode: mode, onScanned: onScanned) }
    func updateNSView(_ nsView: MacOCRView, context: Context) {}
}

final class MacOCRView: NSView, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let mode:      CameraOCRView.Mode
    private let onScanned: (String) -> Void

    private var session:      AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let ocrQueue     = DispatchQueue(label: "intake.mac.ocr",     qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "intake.mac.session", qos: .userInitiated)
    private var isConfiguringSession = false

    private var cameraIsLive     = false
    private var hasScanned       = false
    private var accumulatedLines = [String]()
    private var frameCount       = 0
    private let maxFrames        = 20
    private var lastOCRTime: Date = .distantPast
    private let ingredientScanTimeout: TimeInterval = 15
    private var ingredientScanStartedAt: Date?

    private let statusLabel = NSTextField(labelWithString: "Scanning…")
    private let borderLayer = CAShapeLayer()
    private let dimLayer    = CAShapeLayer()

    init(mode: CameraOCRView.Mode, onScanned: @escaping (String) -> Void) {
        self.mode      = mode
        self.onScanned = onScanned
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setupOverlay()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
        if let s = session { previewLayer?.session = s }
        updateScanOverlay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.checkAndStart() }
        } else {
            stopSession()
        }
    }

    private func checkAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                DispatchQueue.main.async { ok ? self?.startSession() : self?.showDenied() }
            }
        default: showDenied()
        }
    }

    private func findCamera() -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) { types.append(.external) }
        else { types.append(.externalUnknown) }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices

        func score(_ d: AVCaptureDevice) -> Int {
            var s = 0; let name = d.localizedName.lowercased()
            if d.deviceType == .builtInWideAngleCamera { s += 100 }
            if name.contains("facetime") || name.contains("built-in") { s += 40 }
            if name.contains("continuity") || name.contains("desk view") || name.contains("iphone") { s -= 60 }
            if #available(macOS 14.0, *), d.deviceType == .external { s -= 20 }
            return s
        }
        let filtered = devices.filter { d in
            let n = d.localizedName.lowercased()
            return !n.contains("continuity") && !n.contains("desk view") && !n.contains("iphone")
        }
        return (filtered.isEmpty ? devices : filtered).max(by: { score($0) < score($1) })
    }

    private func startSession() {
        DispatchQueue.main.async { self.cameraIsLive = false }
        hasScanned = false
        frameCount = 0
        accumulatedLines.removeAll()
        ingredientScanStartedAt = nil
        lastOCRTime = .distantPast
        if let s = session {
            if !s.isRunning {
                sessionQueue.async { [weak self] in
                    guard let self else { return }
                    s.startRunning()
                    DispatchQueue.main.async { self.cameraIsLive = true }
                }
            } else { cameraIsLive = true }
            return
        }
        guard let device = findCamera(),
              let input  = try? AVCaptureDeviceInput(device: device) else { showDenied(); return }

        let s = AVCaptureSession()
        isConfiguringSession = true
        s.beginConfiguration()
        guard s.canAddInput(input) else { s.commitConfiguration(); isConfiguringSession = false; showDenied(); return }
        s.addInput(input)
        for preset in [AVCaptureSession.Preset.hd1280x720, .high, .medium] {
            if s.canSetSessionPreset(preset) { s.sessionPreset = preset; break }
        }
        let out = AVCaptureVideoDataOutput()
        out.setSampleBufferDelegate(self, queue: ocrQueue)
        out.alwaysDiscardsLateVideoFrames = true
        if s.canAddOutput(out) { s.addOutput(out) }
        s.commitConfiguration(); isConfiguringSession = false

        let preview = AVCaptureVideoPreviewLayer(session: s)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewLayer?.removeFromSuperlayer()
            self.layer?.insertSublayer(preview, at: 0)
            self.previewLayer = preview; self.session = s
            self.updateScanOverlay()
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                s.startRunning()
                DispatchQueue.main.async { self.cameraIsLive = true }
            }
        }
    }

    private func stopSession() {
        cameraIsLive = false
        let oldSession = session; let oldPreview = previewLayer
        session = nil; previewLayer = nil
        safeStopSession(oldSession)
        sessionQueue.async {
            if let s = oldSession {
                if self.isConfiguringSession { return }
                s.beginConfiguration()
                s.inputs.forEach  { s.removeInput($0) }
                s.outputs.forEach { s.removeOutput($0) }
                s.commitConfiguration()
            }
        }
        DispatchQueue.main.async { oldPreview?.removeFromSuperlayer() }
    }

    private func safeStopSession(_ session: AVCaptureSession?) {
        sessionQueue.async { [weak self] in
            guard let self, let session else { return }
            if self.isConfiguringSession {
                self.sessionQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.safeStopSession(session) }
                return
            }
            if session.isRunning { session.stopRunning() }
        }
    }

    private func setupOverlay() {
        dimLayer.fillRule    = .evenOdd
        dimLayer.fillColor   = NSColor.black.withAlphaComponent(0.55).cgColor
        borderLayer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.90).cgColor
        borderLayer.fillColor   = NSColor.clear.cgColor
        borderLayer.lineWidth   = 2.5
        layer?.addSublayer(dimLayer); layer?.addSublayer(borderLayer)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor       = NSColor.white.withAlphaComponent(0.70)
        statusLabel.font            = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.alignment       = .center
        statusLabel.backgroundColor = .clear
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -80),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
    }
    private func scanRect(in r: CGRect) -> CGRect {
        switch mode {
        case .ingredients:
            let sidePad = max(min(r.width * 0.015, 8), 3)
            let scanW = r.width - sidePad * 2
            let scanH = min(max(scanW * 0.82, r.height * 0.62), r.height * 0.80)
            return CGRect(x: (r.width - scanW) / 2,
                          y: max((r.height - scanH) / 2 - r.height * 0.01, 4),
                          width: scanW, height: scanH)
        case .expiryDate:
            let scanW = r.width  * 0.88
            let scanH = scanW * 0.52
            return CGRect(x: (r.width - scanW) / 2,
                          y: (r.height - scanH) / 2 - r.height * 0.04,
                          width: scanW, height: scanH)
        }
    }

    private func updateScanOverlay() {
        guard bounds.width > 20, bounds.height > 20 else { return }
        let scanR = scanRect(in: bounds)

        let path = CGMutablePath()
        path.addRect(bounds)
        path.addPath(CGPath(roundedRect: scanR, cornerWidth: 14, cornerHeight: 14, transform: nil))
        dimLayer.path    = path
        borderLayer.path = CGPath(roundedRect: scanR, cornerWidth: 14, cornerHeight: 14, transform: nil)
    }

    private func showDenied() {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = "Camera access denied — go to System Settings → Privacy → Camera"
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !hasScanned, cameraIsLive else { return }
        let now = Date()
        if mode == .ingredients {
            if ingredientScanStartedAt == nil { ingredientScanStartedAt = now }
            if let started = ingredientScanStartedAt,
               now.timeIntervalSince(started) >= ingredientScanTimeout {
                hasScanned = true
                DispatchQueue.main.async {
                    self.statusLabel.stringValue = "Ingredient cannot be found."
                    self.onScanned(ingredientNotFoundToken)
                }
                return
            }
        }
        guard now.timeIntervalSince(lastOCRTime) >= 0.3 else { return }
        lastOCRTime = now
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let req = VNRecognizeTextRequest { [weak self] r, _ in
            guard let self, !self.hasScanned else { return }
            let lines = (r.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            self.processLines(lines)
        }
        req.recognitionLevel       = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages   = ["en-US", "en-GB", "en-IN"]
        req.minimumTextHeight      = 0.002
        try? VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req])
    }

    private func processLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        frameCount += 1
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count > 1, !accumulatedLines.contains(t) { accumulatedLines.append(t) }
        }

        guard hasIngredientKeyword(in: accumulatedLines) else {
            if frameCount >= 3 {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Ingredient word isn't available to scan." }
            }
            if frameCount >= maxFrames { accumulatedLines.removeAll(); frameCount = 0 }
            return
        }

        DispatchQueue.main.async { self.statusLabel.stringValue = "Scanning… (\(self.frameCount)/\(self.maxFrames))" }
        if let block = extractIngredientBlock(fromLines: accumulatedLines), looksLike(block) {
            if block.count >= 35 || frameCount >= 6 || frameCount >= maxFrames { fire(block); return }
        }
        if frameCount >= maxFrames {
            accumulatedLines.removeAll(); frameCount = 0
            DispatchQueue.main.async { self.statusLabel.stringValue = "Scan near 'Ingredients' label only" }
        }
    }

    private func fire(_ text: String) {
        let cleaned = cleanedIngredientText(from: text)
        let validIngredients = validatedIngredients(from: cleaned)
        guard !validIngredients.isEmpty else {
            accumulatedLines.removeAll(); frameCount = 0
            DispatchQueue.main.async { self.statusLabel.stringValue = "Scanning… hold steady on ingredients list." }
            return
        }
        hasScanned = true
        DispatchQueue.main.async {
            self.statusLabel.stringValue = "Captured! ✓"
            let finalText = validIngredients.joined(separator: ", ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.onScanned(finalText) }
        }
    }

    private func looksLike(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 12 { return false }
        let blocked = ["may contain", "allergen", "allergy advice", "nutrition facts", "nutritional information"]
        if blocked.contains(where: { trimmed.lowercased().contains($0) }) { return false }
        return trimmed.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.count >= 2
    }

    private func extractIngredientBlock(fromLines lines: [String]) -> String? {
        let keywordHints = [
            "ingredients", "ingredient", "ingrients", "ingredints",
            "ingrient", "ingrident", "ingridient", "ingredent",
            "ingredi", "ingred", "ingre", "ingri"
        ]
        let stopHints = [
            "nutrition", "nutritional", "allergen", "allergy", "may contain", "contains",
            "serving", "storage", "direction", "manufactured", "mfg", "expiry", "exp", "best before"
        ]

        var startIndex: Int?
        for (idx, line) in lines.enumerated() {
            if keywordHints.contains(where: { normalizeIngredientOCR(line).contains($0) }) {
                startIndex = idx; break
            }
        }
        guard let start = startIndex else { return nil }

        var chunks: [String] = []
        let head = stripIngredientKeyword(from: lines[start])
        if !head.isEmpty { chunks.append(head) }

        let end = min(lines.count - 1, start + 8)
        if start < end {
            for idx in (start + 1)...end {
                let line = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                if stopHints.contains(where: { line.lowercased().contains($0) }) { break }
                chunks.append(line)
            }
        }

        var merged = chunks.joined(separator: ", ")
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: "|", with: ",")
            .replacingOccurrences(of: " ,", with: ",")
        if let stopRange = firstStopRange(in: merged.lowercased(), stopHints: stopHints) {
            merged = String(merged[..<stopRange.lowerBound])
        }
        return merged.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripIngredientKeyword(from line: String) -> String {
        let patterns = ["ingredients", "ingredient", "ingrident", "ingridient", "ingredi", "ingri", "ingred"]
        let lower = line.lowercased()
        for p in patterns {
            if let r = lower.range(of: p) {
                var tail = String(line[r.upperBound...])
                while let first = tail.first, ":- .;".contains(first) { tail.removeFirst() }
                return tail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeIngredientOCR(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: "1", with: "i")
            .replacingOccurrences(of: "|", with: "i")
            .replacingOccurrences(of: "!", with: "i")
            .replacingOccurrences(of: "0", with: "o")
            .replacingOccurrences(of: "5", with: "s")
    }

    private func hasIngredientKeyword(in lines: [String]) -> Bool {
        let hints = [
            "ingredients", "ingredient", "ingrients", "ingredints",
            "ingrient", "ingrident", "ingridient", "ingredent",
            "ingredi", "ingred", "ingre", "ingri"
        ]
        return lines.contains { line in
            let n = normalizeIngredientOCR(line)
            return hints.contains(where: { n.contains($0) })
        }
    }

    private func firstStopRange(in text: String, stopHints: [String]) -> Range<String.Index>? {
        stopHints.compactMap { text.range(of: $0) }.min(by: { $0.lowerBound < $1.lowerBound })
    }

    private func cleanedIngredientText(from raw: String) -> String {
        let uiNoise = ["share", "save", "panel", "generally safe", "food ingredient",
                       "ingredient analysis", "ingredients found", "nutrition facts"]
        return raw
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
            .filter { token in
                let lower = token.lowercased()
                if uiNoise.contains(where: { lower.contains($0) }) { return false }
                let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
                let digits  = token.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
                if letters < 1 { return false }
                if digits > 0 && digits * 3 > max(letters, 1) { return false }
                if token.filter({ $0 == " " }).count > 4 { return false }
                return true
            }
            .joined(separator: ", ")
    }

    private func validatedIngredients(from text: String) -> [String] {
        let cleanedParts = text.split(separator: ",").map { String($0) }
            .map { sanitizeIngredientToken($0) }.filter { !$0.isEmpty }
        guard !cleanedParts.isEmpty else { return [] }
        var out: [String] = []
        for token in cleanedParts {
            guard let normalized = IngredientInsightEngine.shared.normalizedOCRIngredientPhrase(token) else { continue }
            if !out.contains(normalized) { out.append(normalized) }
        }
        return Array(out.prefix(24))
    }

    private func sanitizeIngredientToken(_ token: String) -> String {
        let stopWords: Set<String> = ["and", "with", "contains", "contain", "may", "from", "per", "of", "the"]
        let units: Set<String>     = ["mg", "g", "kg", "ml", "l", "mcg", "%"]
        return token.lowercased()
            .replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .split(separator: " ").map(String.init)
            .map(correctedIngredientOCRWord)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty && !$0.allSatisfy(\.isNumber) }
            .filter { !stopWords.contains($0) && !units.contains($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
