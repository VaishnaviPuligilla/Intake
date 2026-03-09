// Real-time camera-based expiry and ingredient scanning view.
// Supports OCR-based expiry detection, manual fallback entry,
// and persistence with notification scheduling.

import SwiftUI
import SwiftData


enum ScanContext {
    case expiry
    case health
}

struct ScanView: View {
    let context: ScanContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.scenePhase)   private var scenePhase

    
    @StateObject private var camera = CameraController()
    @State private var cameraError: CameraError?
    @State private var lowLight        = false
    @State private var detectedExpiry: Date?
    @State private var showNameEntry   = false
    @State private var showNotificationDeniedAlert = false

    
    @State private var scannedIngredients   = ""
    @State private var showIngredientResult = false
    @State private var showIngredientNotFoundAlert = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if context == .health {
                healthScanBody
            } else {
                expiryScanBody
            }
        }
        .onAppear {
            if context == .expiry {
                setupExpiryCamera()
                cameraError = nil
                camera.start()
            }
        }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if context == .expiry,
               phase == .active,
               camera.session == nil,
               cameraError == nil,
               !showNameEntry {
                camera.start()
            }
        }
        .sheet(isPresented: $showNameEntry) {
            if let expiry = detectedExpiry {
                ProductNameEntryView(
                    detectedExpiry: expiry,
                    onCancel: { dismiss() }
                ) { name, resolvedExpiry, reminderAt in
                    saveExpiryItem(name: name, expiry: resolvedExpiry, reminderAt: reminderAt) { scheduledOK in
                        if scheduledOK { dismiss() }
                    }
                }
            }
        }
        .sheet(isPresented: $showIngredientResult) {
            IngredientResultView(
                ingredientsText: scannedIngredients,
                onSave: { name in
                    saveHealthEntry(name: name, ingredients: scannedIngredients)
                    dismiss()
                },
                onDismiss: { dismiss() }
            )
        }
        .alert("Notifications Disabled", isPresented: $showNotificationDeniedAlert) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable notifications for Intake in system settings to receive expiry alerts in and out of the app.")
        }
    }

    
    private var expiryScanBody: some View {
        ZStack {
            if cameraError == nil {
                CameraPreviewRepresentable(controller: camera)
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                expiryScanOverlay
            }
            if lowLight { lowLightBanner }
            if let err = cameraError { cameraErrorView(err) }
        }
    }


    private var healthScanBody: some View {
        ZStack {
            CameraOCRView(mode: .ingredients) { text in
                if text == ingredientNotFoundToken {
                    HapticManager.shared.error()
                    showIngredientNotFoundAlert = true
                    return
                }
                scannedIngredients = text
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showIngredientResult = true
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.82))
                            .padding(.top, 14)
                            .padding(.trailing, 16)
                    }
                }
                Spacer()
            }
        }
        .alert("Ingredient Not Found", isPresented: $showIngredientNotFoundAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Ingredient cannot be found. Please rescan near the ingredients label.")
        }
    }

    
    private func setupExpiryCamera() {
        camera.onLowLight = { isLow in withAnimation { lowLight = isLow } }
        camera.onError    = { err  in withAnimation { cameraError = err  } }
        camera.onExpiryDetected = { date in
            DispatchQueue.main.async {
                HapticManager.shared.success()
                self.detectedExpiry = date
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showNameEntry = true
                }
            }
        }
    }

   
    private var expiryScanOverlay: some View {
        GeometryReader { geo in
            let W = geo.size.width.isFinite ? geo.size.width : 1
            let H = geo.size.height.isFinite ? geo.size.height : 1

            let sidePad: CGFloat = max(min(W * 0.02, 10), 6)
            let rawScanW = W - sidePad * 2
            let scanW    = max(min(rawScanW, W - 8), 260)
            let rawScanH = scanW * 0.76
            let scanH    = max(min(rawScanH, H * 0.72), 240)
            let scanX    = sidePad
            let scanY    = max((H - scanH) / 2 - 4, 0)

            ZStack {
                Canvas { ctx, size in
                    var path = Path(CGRect(origin: .zero, size: size))
                    path.addRoundedRect(
                        in: CGRect(x: scanX, y: scanY, width: scanW, height: scanH),
                        cornerSize: CGSize(width: 14, height: 14)
                    )
                    ctx.fill(path, with: .color(.black.opacity(0.55)),
                             style: FillStyle(eoFill: true))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.90), lineWidth: 2.5)
                    .frame(width: scanW, height: scanH)
                    .position(x: W / 2, y: min(max(scanY + scanH / 2, 0), H))

                CornerBrackets()
                    .stroke(Color.green, lineWidth: 3.5)
                    .frame(width: scanW, height: scanH)
                    .position(x: W / 2, y: min(max(scanY + scanH / 2, 0), H))

                AnimatedScanLine(
                    scanRect: CGRect(x: scanX, y: scanY, width: scanW, height: scanH)
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Spacer().frame(height: max(scanY - 40, 52))
                    Text("EXPIRY DATE SCANNER")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(.green.opacity(0.85))
                    Spacer()
                }

                VStack(spacing: 0) {
                    Spacer().frame(height: max(scanY + scanH + 14, 0))
                    Text("Point at the expiry date on the package")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }

                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.80))
                                .padding(.top, 14)
                                .padding(.trailing, 16)
                        }
                    }
                    Spacer()
                }

                VStack {
                    Spacer()
                    Button {
                        HapticManager.shared.light()
                        detectedExpiry = Date().addingTimeInterval(60 * 60 * 24 * 30)
                        showNameEntry  = true
                    } label: {
                        Label("Enter expiry manually", systemImage: "keyboard")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.vertical, 14)
                            .padding(.horizontal, 28)
                            .background(
                                Capsule().fill(Color.white.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }

    private var lowLightBanner: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "sun.min.fill").foregroundColor(.yellow)
                Text("Not enough light to scan.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.80)))
            .padding(.top, 60)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    
    @ViewBuilder
    private func cameraErrorView(_ error: CameraError) -> some View {
        VStack(spacing: 20) {
            Image(systemName: error.icon)
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.4))
            Text(error.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text(error.message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            #if os(iOS)
            if error == .permissionDenied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundColor(.green)
                .font(.system(size: 15, weight: .semibold))
            }
            #endif
            Button {
                HapticManager.shared.light()
                detectedExpiry = Date().addingTimeInterval(60 * 60 * 24 * 30)
                showNameEntry  = true
            } label: {
                Text("Enter manually instead")
                    .foregroundColor(.white.opacity(0.55))
                    .font(.system(size: 14))
            }
        }
        .padding(32)
    }

    private func saveExpiryItem(
        name: String,
        expiry: Date,
        reminderAt: Date?,
        completion: @escaping (Bool) -> Void
    ) {
        let cal = Calendar.current
        if cal.startOfDay(for: expiry) < cal.startOfDay(for: Date()) {
            HapticManager.shared.error()
            completion(false)
            return
        }

        let safeExpiry = Calendar.current.date(
            bySettingHour: 12, minute: 0, second: 0, of: expiry
        ) ?? expiry
        let item = ScannedItem(productName: name, expiryDate: safeExpiry)
        item.reminderAt = reminderAt
        modelContext.insert(item)
        do {
            try modelContext.save()
            NotificationManager.shared.scheduleNotifications(for: item, reminderAt: reminderAt) { result in
                if case .permissionDenied = result {
                    showNotificationDeniedAlert = true
                    completion(false)
                } else {
                    completion(true)
                }
            }
            HapticManager.shared.success()
        } catch {
            HapticManager.shared.error()
            print("Save error: \(error)")
            completion(false)
        }
    }


    private func saveHealthEntry(name: String, ingredients: String) {
        let insight = IngredientInsightEngine.shared.analyze(ingredients: ingredients)
        let entry   = HealthEntry(
            productName:     name,
            ingredientsText: ingredients,
            riskLevel:       insight.risk
        )
        modelContext.insert(entry)
        try? modelContext.save()
        HapticManager.shared.success()
    }
}


private struct AnimatedScanLine: View {
    let scanRect: CGRect
    @State private var offset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, .green.opacity(0.80), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: scanRect.width - 32, height: 2)
            .position(x: scanRect.midX, y: scanRect.minY + offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    offset = scanRect.height - 4
                }
            }
    }
}

struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len: CGFloat = 24
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

#Preview {
    ScanView(context: .expiry)
        .modelContainer(for: ScannedItem.self, inMemory: true)
}
