import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    let onContinue: () -> Void

    private var accent: Color { Color(uiColor: AppTheme.accent) }
    private var surface: Color { Color(uiColor: AppTheme.backgroundRaise) }
    private var primary: Color { Color(uiColor: AppTheme.primaryText) }
    private var secondary: Color { Color(uiColor: AppTheme.secondaryText) }
    private var muted: Color { Color(uiColor: AppTheme.tertiaryText) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(uiColor: AppTheme.background), Color(red: 0.035, green: 0.055, blue: 0.085)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sessionCard
                    expirationCard
                    continueButton
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NYXEL EXTERNAL")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(primary)
                Text("SECURE OPERATIONS · TEST BUILD · v\(appState.appVersion)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(muted)
            }
            Spacer()
            Button { appState.logout() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .accessibilityLabel("Cerrar sesión")
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: appState.isExpired ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(appState.isExpired ? Color(uiColor: AppTheme.failure) : accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.isExpired ? "SESIÓN EXPIRADA" : "SESIÓN ACTIVA")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(appState.isExpired ? Color(uiColor: AppTheme.failure) : accent)
                    Text(appState.isExpired ? "Actualiza tu acceso para continuar." : "Todo listo para comenzar.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(secondary)
                }
                Spacer()
                Circle()
                    .fill(appState.isExpired ? Color(uiColor: AppTheme.failure) : Color(uiColor: AppTheme.success))
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 12) {
                detail(icon: "key.fill", label: "KEY", value: maskedKey)
                detail(icon: "iphone", label: "DISPOSITIVO", value: deviceName)
            }
        }
        .padding(18)
        .background(surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accent.opacity(0.20), lineWidth: 1))
    }

    private func detail(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(accent.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(muted)
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(primary.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expirationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ACCESO VÁLIDO HASTA")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(muted)
                Spacer()
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appState.isExpired ? Color(uiColor: AppTheme.failure) : accent)
            }

            Text(appState.isExpired ? "Acceso vencido" : formatExpirationDate(appState.expirationDate()))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(appState.isExpired ? Color(uiColor: AppTheme.failure) : primary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(appState.isExpired ? "—" : "\(appState.remainingDays)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(appState.isExpired ? Color(uiColor: AppTheme.failure) : accent)
                Text(appState.isExpired ? "" : (appState.remainingDays == 1 ? "día restante" : "días restantes"))
                    .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: appState.isInjected ? "checkmark.circle.fill" : "circle.dashed")
                Text(appState.isInjected ? "Entorno preparado" : "Entorno pendiente")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(appState.isInjected ? Color(uiColor: AppTheme.success) : secondary)

            if !appState.isExpired && appState.remainingDays <= 3 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text("Tu acceso está próximo a vencer.")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(uiColor: AppTheme.warm))
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: 9) {
                Text("CONTINUAR")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(0.7)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color(uiColor: AppTheme.background))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .disabled(appState.isExpired)
        .opacity(appState.isExpired ? 0.42 : 1.0)
        .accessibilityLabel("Continuar a operación")
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
            Text("Sesión protegida en este dispositivo")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(muted)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var maskedKey: String {
        let cleanKey = appState.currentKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanKey.count > 7 else { return cleanKey.isEmpty ? "NO DISPONIBLE" : "••••••" }
        return "••••" + cleanKey.suffix(4)
    }

    private var deviceName: String { UIDevice.current.localizedModel.uppercased() }

    private func formatExpirationDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "es_MX")
        return formatter.string(from: date)
    }
}
