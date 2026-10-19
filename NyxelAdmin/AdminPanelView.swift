import SwiftUI

private enum AdminPalette {
    static let background = Color(red: 0.025, green: 0.040, blue: 0.065)
    static let panel = Color(red: 0.055, green: 0.080, blue: 0.115)
    static let raised = Color(red: 0.080, green: 0.110, blue: 0.145)
    static let mint = Color(red: 0.36, green: 0.96, blue: 0.75)
    static let blue = Color(red: 0.30, green: 0.66, blue: 0.98)
    static let gold = Color(red: 1.00, green: 0.73, blue: 0.33)
    static let muted = Color.white.opacity(0.58)
    static let stroke = Color.white.opacity(0.10)
}

struct AdminPanelView: View {
    @StateObject private var store = AdminPanelStore()
    @State private var selectedRoute: String? = "/dashboard"

    var body: some View {
        ZStack {
            AdminPalette.background.ignoresSafeArea()
            Group {
                if store.isCheckingSession {
                    launchScreen
                } else if !store.isAuthenticated {
                    AdminLoginView(store: store)
                } else {
                    appShell
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(AdminPalette.mint)
        .task { await store.restoreSession() }
        .onChange(of: selectedRoute) { route in
            guard store.isAuthenticated, let route else { return }
            Task { await store.load(route) }
        }
    }

    private var launchScreen: some View {
        ZStack {
            AdminPalette.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "key.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AdminPalette.mint)
                    .frame(width: 68, height: 68)
                    .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 22))
                ProgressView().tint(AdminPalette.mint)
                Text("Conectando con Nyxel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AdminPalette.muted)
            }
        }
    }

    private var appShell: some View {
        NavigationSplitView {
            List(selection: $selectedRoute) {
                ForEach(sectionNames, id: \.self) { section in
                    let items = store.menuItems.filter { $0.section == section }
                    if !items.isEmpty {
                        Section(header: Text(section).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.1)) {
                            ForEach(items) { item in
                                NavigationLink(value: item.route) {
                                    Label(item.title, systemImage: item.symbol)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(selectedRoute == item.route ? AdminPalette.mint : .white.opacity(0.88))
                                }
                                .listRowBackground(selectedRoute == item.route ? AdminPalette.mint.opacity(0.12) : Color.clear)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AdminPalette.background)
            .listStyle(.sidebar)
            .navigationTitle("Nyxel Admin")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { accountCard }
            .navigationSplitViewColumnWidth(min: 240, ideal: 275, max: 330)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .background(AdminPalette.background)
        .toolbarBackground(AdminPalette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NYXEL ADMIN")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(AdminPalette.mint)
                    Text(selectedTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                Button {
                    guard let selectedRoute else { return }
                    Task { await store.load(selectedRoute) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Actualizar")
                .disabled(store.isLoading)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(AdminPalette.background)

            if store.isLoading {
                ProgressView().progressViewStyle(.linear).tint(AdminPalette.mint)
            }

            if let message = store.errorMessage {
                InlineNotice(text: message, style: .warning) {
                    store.errorMessage = nil
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

            if let page = store.page {
                NativeAdminPageView(
                    page: page,
                    role: store.role,
                    isLoading: store.isLoading,
                    onRefresh: { await store.load(selectedRoute ?? "/dashboard") },
                    onNavigate: { route in selectedRoute = route },
                    onSubmit: { form, values in await store.submit(form, values: values, currentRoute: selectedRoute ?? "/dashboard") }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(AdminPalette.mint)
                    Text("Sin contenido")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Selecciona una sección para cargar su información.")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminPalette.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AdminPalette.background)
            }
        }
        .background(AdminPalette.background)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    Task { await store.logout() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(AdminPalette.muted)
                }
                .accessibilityLabel("Cerrar sesión")
            }
        }
    }

    private var accountCard: some View {
        HStack(spacing: 12) {
            Image(systemName: store.role == .superadmin ? "crown.fill" : "person.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(store.role == .superadmin ? AdminPalette.gold : AdminPalette.mint)
                .frame(width: 38, height: 38)
                .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("Sesión protegida")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(store.role == .superadmin ? "Superadministrador" : "Vendedor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdminPalette.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(AdminPalette.panel)
        .overlay(alignment: .top) { Rectangle().fill(AdminPalette.stroke).frame(height: 1) }
    }

    private var selectedTitle: String {
        store.menuItems.first(where: { $0.route == selectedRoute })?.title
            ?? store.page?.title
            ?? "Inicio"
    }

    private var sectionNames: [String] {
        ["GENERAL", "OPERACIÓN", "ADMINISTRACIÓN", "SISTEMA", "SEGURIDAD"]
    }
}

@MainActor
private final class AdminPanelStore: ObservableObject {
    @Published var isCheckingSession = true
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var isLoggingIn = false
    @Published var page: AdminPageModel?
    @Published var role: AdminRole = .vendor
    @Published var errorMessage: String?

    private let client = AdminWorkerClient.shared

    var menuItems: [AdminPageDefinition] {
        AdminPageDefinition.all.filter { role == .superadmin || !$0.superadminOnly }
    }

    func restoreSession() async {
        guard isCheckingSession else { return }
        defer { isCheckingSession = false }
        do {
            let dashboard = try await client.restoreSession()
            guard !dashboard.isLoginPage else {
                isAuthenticated = false
                return
            }
            page = dashboard
            isAuthenticated = true
            role = await client.discoverRole()
        } catch {
            isAuthenticated = false
            errorMessage = error.localizedDescription
        }
    }

    func login(username: String, password: String) async {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else {
            errorMessage = "Escribe tu usuario y contraseña."
            return
        }
        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }
        do {
            let dashboard = try await client.login(username: username, password: password)
            page = dashboard
            isAuthenticated = true
            role = await client.discoverRole()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func load(_ route: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.loadPage(route)
            if loaded.isLoginPage {
                isAuthenticated = false
                page = nil
                errorMessage = "Tu sesión venció. Inicia sesión de nuevo."
                return
            }
            if loaded.isForbidden {
                errorMessage = AdminWorkerError.forbidden.localizedDescription
                page = loaded
                return
            }
            page = loaded
        } catch {
            if let workerError = error as? AdminWorkerError, case .sessionExpired = workerError {
                isAuthenticated = false
                page = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    func submit(_ form: AdminForm, values: [String: String], currentRoute: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.submit(form: form, values: values)
            if result.isLoginPage {
                isAuthenticated = false
                page = nil
                errorMessage = "Tu sesión venció. Inicia sesión de nuevo."
                return
            }
            if result.route == currentRoute || AdminPageDefinition.knownRoutes.contains(result.route) {
                page = result
            } else {
                page = try await client.loadPage(currentRoute)
            }
        } catch {
            if let workerError = error as? AdminWorkerError, case .sessionExpired = workerError {
                isAuthenticated = false
                page = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    func logout() async {
        await client.logout()
        isAuthenticated = false
        isLoading = false
        page = nil
        errorMessage = nil
        role = .vendor
    }
}

private struct AdminLoginView: View {
    @ObservedObject var store: AdminPanelStore
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        ZStack {
            AdminPalette.background.ignoresSafeArea()
            GeometryReader { proxy in
                Circle()
                    .fill(AdminPalette.mint.opacity(0.10))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .position(x: proxy.size.width * 0.15, y: 90)
                Circle()
                    .fill(AdminPalette.blue.opacity(0.10))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .position(x: proxy.size.width * 0.90, y: proxy.size.height * 0.83)
            }
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AdminPalette.mint)
                            .frame(width: 76, height: 76)
                            .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(RoundedRectangle(cornerRadius: 24).stroke(AdminPalette.mint.opacity(0.24), lineWidth: 1))
                        Text("NYXEL ADMIN")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white)
                        Text("Control nativo de tu Worker")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AdminPalette.muted)
                    }
                    .padding(.bottom, 6)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Iniciar sesión")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        credentialField(title: "Usuario", symbol: "person", isSecure: false)
                            .focused($focusedField, equals: .username)
                            .textContentType(.username)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                        credentialField(title: "Contraseña", symbol: "lock", isSecure: true)
                            .focused($focusedField, equals: .password)
                            .textContentType(.password)
                            .submitLabel(.go)
                            .onSubmit { Task { await submitLogin() } }

                        Text("Usa la credencial asignada a Nyxel Admin. La contraseña de superadministrador es distinta a la del sitio web.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AdminPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if let error = store.errorMessage {
                            InlineNotice(text: error, style: .warning)
                        }

                        Button {
                            Task { await submitLogin() }
                        } label: {
                            HStack(spacing: 10) {
                                if store.isLoggingIn { ProgressView().tint(AdminPalette.background) }
                                Text(store.isLoggingIn ? "Conectando…" : "Entrar al panel")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(AdminPalette.background)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AdminPalette.mint, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isLoggingIn)
                    }
                    .padding(22)
                    .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(AdminPalette.stroke, lineWidth: 1))
                    .frame(maxWidth: 430)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill").foregroundStyle(AdminPalette.mint)
                        Text("La autenticación y los permisos los valida el Worker.")
                            .foregroundStyle(AdminPalette.muted)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 44)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func credentialField(title: String, symbol: String, isSecure: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AdminPalette.mint)
                .frame(width: 20)
            Group {
                if isSecure {
                    SecureField(title, text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField(title, text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 15)
        .frame(height: 52)
        .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(AdminPalette.stroke, lineWidth: 1))
    }

    private func submitLogin() async {
        focusedField = nil
        await store.login(username: username, password: password)
        if store.isAuthenticated { password = "" }
    }
}

private struct NativeAdminPageView: View {
    let page: AdminPageModel
    let role: AdminRole
    let isLoading: Bool
    let onRefresh: () async -> Void
    let onNavigate: (String) -> Void
    let onSubmit: (AdminForm, [String: String]) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHero
                if page.route == "/dashboard" { quickActions }
                ForEach(Array(page.messages.enumerated()), id: \.offset) { item in
                    InlineNotice(text: item.element, style: .info)
                }
                if !page.metrics.isEmpty { metricsGrid }
                if !page.paragraphs.isEmpty { summaryCard }
                ForEach(page.tables) { table in
                    AdminTableCard(table: table)
                }
                ForEach(page.forms) { form in
                    NativeAdminFormCard(form: form, onSubmit: onSubmit)
                }
                if page.tables.isEmpty && page.forms.isEmpty && page.metrics.isEmpty && page.paragraphs.isEmpty {
                    emptyState
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(AdminPalette.background)
        .refreshable { await onRefresh() }
    }

    private var pageHero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: AdminPageDefinition.all.first(where: { $0.route == page.route })?.symbol ?? "square.grid.2x2.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AdminPalette.mint)
                .frame(width: 50, height: 50)
                .background(AdminPalette.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(page.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle = page.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdminPalette.muted)
                } else {
                    Text(page.route == "/dashboard" ? "Tu centro de control, conectado al Worker." : "Interfaz nativa · datos y acciones validados por el Worker.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdminPalette.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [AdminPalette.raised, AdminPalette.panel], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(AdminPalette.stroke, lineWidth: 1))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("ACCESOS RÁPIDOS", subtitle: "Atajos a las tareas frecuentes")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                quickAction("Crear key", symbol: "plus", route: "/keys/create", tint: AdminPalette.mint)
                quickAction("Generar lote", symbol: "square.stack.3d.up", route: "/keys/generate", tint: AdminPalette.blue)
                quickAction("Keys", symbol: "key.horizontal", route: "/keys", tint: AdminPalette.gold)
                quickAction("Trials", symbol: "clock", route: "/keys/create-trial", tint: AdminPalette.mint)
            }
        }
    }

    private func quickAction(_ title: String, symbol: String, route: String, tint: Color) -> some View {
        Button { onNavigate(route) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(AdminPalette.muted)
            }
            .padding(13)
            .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(AdminPalette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("RESUMEN", subtitle: "Indicadores disponibles en el Worker")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(page.metrics) { metric in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(metric.label.isEmpty ? "Indicador" : metric.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdminPalette.muted)
                            .lineLimit(2)
                        Text(metric.value)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
                    .padding(15)
                    .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(AdminPalette.stroke, lineWidth: 1))
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("DETALLES", subtitle: "Información del servicio")
            ForEach(Array(page.paragraphs.prefix(8).enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(AdminPalette.mint)
            Text("No hay datos para mostrar")
                .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text("Prueba actualizar o vuelve a iniciar sesión si tu sesión venció.")
                .font(.system(size: 12)).foregroundStyle(AdminPalette.muted).multilineTextAlignment(.center)
        }
        .padding(25)
        .frame(maxWidth: .infinity)
        .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.2).foregroundStyle(AdminPalette.mint)
            Text(subtitle).font(.system(size: 12, weight: .medium)).foregroundStyle(AdminPalette.muted)
        }
    }
}

private struct AdminTableCard: View {
    let table: AdminTable

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(AdminPalette.blue)
                Text(table.title.isEmpty ? "Registros" : table.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Text("\(table.rows.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(AdminPalette.mint)
            }
            if table.rows.isEmpty {
                Text("Sin registros.").font(.system(size: 12)).foregroundStyle(AdminPalette.muted)
            } else {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowItem in
                    let rowIndex = rowItem.offset
                    let row = rowItem.element
                    VStack(alignment: .leading, spacing: 8) {
                        if let first = row.first, !first.isEmpty {
                            Text(first).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                        }
                        ForEach(Array(row.dropFirst().enumerated()), id: \.offset) { cellItem in
                            if !cellItem.element.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(header(for: cellItem.offset + 1))
                                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(AdminPalette.muted)
                                    Spacer(minLength: 4)
                                    Text(cellItem.element)
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.86))
                                        .multilineTextAlignment(.trailing).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 14))
                    if rowIndex < table.rows.count - 1 { Rectangle().fill(AdminPalette.stroke).frame(height: 1) }
                }
            }
        }
        .padding(16)
        .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(AdminPalette.stroke, lineWidth: 1))
    }

    private func header(for index: Int) -> String {
        guard table.headers.indices.contains(index) else { return "Dato" }
        return table.headers[index]
    }
}

private struct NativeAdminFormCard: View {
    let form: AdminForm
    let onSubmit: (AdminForm, [String: String]) async -> Void

    @State private var values: [String: String]
    @State private var showConfirmation = false
    @State private var localError: String?
    @State private var submitting = false

    init(form: AdminForm, onSubmit: @escaping (AdminForm, [String: String]) async -> Void) {
        self.form = form
        self.onSubmit = onSubmit
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: form.fields.map { ($0.id, $0.value) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: form.isDestructive ? "exclamationmark.triangle.fill" : "slider.horizontal.3")
                    .foregroundStyle(form.isDestructive ? AdminPalette.gold : AdminPalette.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(form.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(form.method == "GET" ? "Consulta" : "Acción conectada al Worker")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(AdminPalette.muted)
                }
                Spacer()
            }
            if form.requiresUpload {
                InlineNotice(text: "Este formulario requiere adjuntar un archivo y no está habilitado en esta versión nativa.", style: .warning)
            }
            ForEach(form.fields) { field in
                fieldControl(field)
            }
            if form.fields.isEmpty && !form.requiresUpload {
                Text("Esta acción se aplica al registro indicado por el Worker.")
                    .font(.system(size: 12)).foregroundStyle(AdminPalette.muted)
            }
            if let localError {
                Text(localError).font(.system(size: 12, weight: .medium)).foregroundStyle(.red.opacity(0.9))
            }
            Button {
                guard validate() else { return }
                if form.needsConfirmation || form.isDestructive { showConfirmation = true }
                else { Task { await submit() } }
            } label: {
                HStack(spacing: 9) {
                    if submitting { ProgressView().tint(AdminPalette.background) }
                    Text(submitting ? "Enviando…" : form.submitTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: form.isDestructive ? "exclamationmark.circle" : "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(form.isDestructive ? Color.white : AdminPalette.background)
                .padding(.horizontal, 15)
                .frame(height: 46)
                .background(form.isDestructive ? Color(red: 0.72, green: 0.20, blue: 0.25) : AdminPalette.mint, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(submitting || form.requiresUpload)
            .alert("Confirmar acción", isPresented: $showConfirmation) {
                Button("Confirmar", role: form.isDestructive ? .destructive : nil) { Task { await submit() } }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("¿Confirmas “\(form.submitTitle)” en el Worker? Revisa los valores antes de continuar.")
            }
        }
        .padding(17)
        .background(AdminPalette.panel, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(form.isDestructive ? AdminPalette.gold.opacity(0.30) : AdminPalette.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private func fieldControl(_ field: AdminFormField) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text(field.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(AdminPalette.muted)
                if field.required { Text("*").foregroundStyle(AdminPalette.gold) }
            }
            switch field.type {
            case "select":
                if field.options.isEmpty {
                    textInput(field)
                } else {
                    Picker(field.label, selection: binding(for: field)) {
                        ForEach(field.options) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AdminPalette.mint)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 12))
                }
            case "checkbox":
                Toggle(field.label, isOn: Binding(
                    get: { values[field.id] == "true" },
                    set: { values[field.id] = $0 ? "true" : "false" }
                ))
                .labelsHidden()
                .tint(AdminPalette.mint)
                .frame(maxWidth: .infinity, alignment: .leading)
            case "textarea":
                TextEditor(text: binding(for: field))
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .frame(minHeight: 88)
                    .padding(8)
                    .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 12))
            case "file":
                Text("Archivo: \(field.placeholder.isEmpty ? field.label : field.placeholder)")
                    .font(.system(size: 12)).foregroundStyle(AdminPalette.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 12))
            default:
                textInput(field)
            }
        }
    }

    private func textInput(_ field: AdminFormField) -> some View {
        Group {
            if field.type == "password" {
                SecureField(field.placeholder.isEmpty ? field.label : field.placeholder, text: binding(for: field))
            } else {
                TextField(field.placeholder.isEmpty ? field.label : field.placeholder, text: binding(for: field))
                    .keyboardType(field.type == "number" ? .numberPad : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(AdminPalette.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private func binding(for field: AdminFormField) -> Binding<String> {
        Binding(get: { values[field.id] ?? field.value }, set: { values[field.id] = $0 })
    }

    private func validate() -> Bool {
        for field in form.fields where field.required {
            if (values[field.id] ?? field.value).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                localError = "Completa el campo “\(field.label)”."
                return false
            }
        }
        localError = nil
        return true
    }

    private func submit() async {
        submitting = true
        localError = nil
        await onSubmit(form, values)
        submitting = false
    }
}

private struct InlineNotice: View {
    enum Style { case info, warning }
    let text: String
    var style: Style = .info
    var onDismiss: (() -> Void)? = nil

    private var tint: Color { style == .warning ? AdminPalette.gold : AdminPalette.mint }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(AdminPalette.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.24), lineWidth: 1))
    }
}
