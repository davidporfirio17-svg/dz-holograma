import SwiftUI

struct KeyGateView: View {
    @EnvironmentObject var appState: AppState
    let onSuccess: () -> Void
    
    @State private var keyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    @State private var versionUnavailable: Bool = false
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            BackgroundParticles()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.cyan.opacity(0.15)).frame(width: 90, height: 90)
                        Circle().strokeBorder(Color.cyan.opacity(0.4), lineWidth: 1.5).frame(width: 90, height: 90)
                        Image(systemName: "syringe.fill").font(.system(size: 36)).foregroundColor(.cyan)
                    }
                    Text("DAVIZIN")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.cyan, Color(red: 0.0, green: 0.7, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .cyan.opacity(0.5), radius: 12)
                    Text("iOS Injector v\(appState.appVersion)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                        logoScale = 1.0
                        logoOpacity = 1.0
                    }
                }
                Spacer().frame(height: 50)
                if versionUnavailable {
                    VStack(spacing: 18) {
                        Image(systemName: "nosign")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("VERSIÓN NO DISPONIBLE")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(1)
                        Text("Esta versión ya no puede iniciar sesión.")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white.opacity(0.6))
                        Button("REINTENTAR") {
                            versionUnavailable = false
                            showError = false
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.cyan))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                } else {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Compatible con tu dispositivo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.green.opacity(0.1)).overlay(Capsule().strokeBorder(Color.green.opacity(0.3), lineWidth: 1)))
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill").foregroundColor(.cyan.opacity(0.7)).font(.system(size: 16))
                        TextField("", text: $keyInput)
                            .placeholder(when: keyInput.isEmpty) {
                                Text("Ingresa tu Key de acceso").foregroundColor(.white.opacity(0.25))
                            }
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .submitLabel(.done)
                            .onSubmit { validateKey() }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1.5)))
                    if showError {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.system(size: 13))
                            Text(errorMessage).font(.system(size: 13)).foregroundColor(.red)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Button(action: validateKey) {
                        ZStack {
                            if isValidating {
                                ProgressView().tint(.black)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.shield.fill")
                                    Text("VALIDAR KEY").font(.system(size: 16, weight: .bold)).tracking(1)
                                }
                                .foregroundColor(.black)
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.cyan, Color(red: 0.0, green: 0.7, blue: 1.0)], startPoint: .leading, endPoint: .trailing))
                            .shadow(color: .cyan.opacity(0.4), radius: 12, y: 4))
                    }
                    .disabled(isValidating || keyInput.isEmpty)
                    .opacity(keyInput.isEmpty ? 0.6 : 1.0)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
                .padding(.horizontal, 20)
                }
                Spacer()
                Text("Nyxel").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.2)).padding(.bottom, 30)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }
    
    private func validateKey() {
        guard !keyInput.isEmpty else { return }
        withAnimation { showError = false }
        isValidating = true
        
        KeyValidator.validateWithSeconds(key: keyInput) { isValid, message, remainingSeconds, _ in
            isValidating = false
            
            if isValid {
                let expirationTimeMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(remainingSeconds * 1000)
                appState.saveKey(keyInput, expirationMs: expirationTimeMs)
                onSuccess()
            } else {
                if KeyValidator.lastValidationWasVersionUnavailable {
                    withAnimation {
                        versionUnavailable = true
                        showError = false
                    }
                } else {
                    errorMessage = message
                    withAnimation { showError = true }
                }
            }
        }
    }
}

struct BackgroundParticles: View {
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color.cyan.opacity(0.03 + Double(i) * 0.01))
                    .frame(width: CGFloat(80 + i * 40))
                    .position(
                        x: geo.size.width * [0.1, 0.9, 0.2, 0.8, 0.5, 0.3][i],
                        y: geo.size.height * [0.1, 0.2, 0.7, 0.8, 0.4, 0.5][i]
                    )
                    .blur(radius: 30)
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(when shouldShow: Bool, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
