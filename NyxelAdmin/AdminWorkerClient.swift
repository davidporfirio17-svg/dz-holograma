import Foundation
import SwiftSoup

struct AdminPageModel {
    let route: String
    let title: String
    let subtitle: String?
    let messages: [String]
    let paragraphs: [String]
    let metrics: [AdminMetric]
    let tables: [AdminTable]
    let forms: [AdminForm]
    let navigationRoutes: Set<String>
    let isLoginPage: Bool
    let isForbidden: Bool
    let statusCode: Int
}

struct AdminMetric: Identifiable {
    let id: String
    let label: String
    let value: String
}

struct AdminTable: Identifiable {
    let id: String
    let title: String
    let headers: [String]
    let rows: [[String]]
}

struct AdminForm: Identifiable {
    let id: String
    let title: String
    let action: String
    let method: String
    let submitTitle: String
    let hiddenFields: [AdminHiddenField]
    let fields: [AdminFormField]
    let requiresUpload: Bool
    let needsConfirmation: Bool

    var isDestructive: Bool {
        let text = "\(title) \(submitTitle) \(action)".lowercased()
        return ["eliminar", "borrar", "delete", "revocar", "ban", "pausar", "kill", "permanente", "desactivar"].contains { text.contains($0) }
    }
}

struct AdminHiddenField {
    let name: String
    let value: String
}

struct AdminFormField: Identifiable {
    let id: String
    let name: String
    let label: String
    let type: String
    let value: String
    let placeholder: String
    let required: Bool
    let options: [AdminFormOption]
}

struct AdminFormOption: Identifiable {
    let id: String
    let title: String
    let value: String
}

enum AdminRole: String {
    case superadmin
    case vendor
}

struct AdminPageDefinition: Identifiable {
    let route: String
    let title: String
    let symbol: String
    let section: String
    let superadminOnly: Bool

    var id: String { route }

    static let all: [AdminPageDefinition] = [
        .init(route: "/dashboard", title: "Inicio", symbol: "square.grid.2x2.fill", section: "GENERAL", superadminOnly: false),
        .init(route: "/live", title: "En vivo", symbol: "dot.radiowaves.left.and.right", section: "GENERAL", superadminOnly: true),
        .init(route: "/usage", title: "Uso", symbol: "chart.bar.fill", section: "GENERAL", superadminOnly: true),
        .init(route: "/keys", title: "Keys", symbol: "key.horizontal.fill", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/keys/create", title: "Crear key", symbol: "plus.rectangle.on.folder", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/keys/generate", title: "Generar lote", symbol: "square.stack.3d.up.fill", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/keys/create-trial", title: "Crear trial", symbol: "clock.badge.checkmark", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/por-vencer", title: "Por vencer", symbol: "hourglass", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/pause-mine", title: "Mis pausas", symbol: "pause.circle.fill", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/trash", title: "Papelera", symbol: "trash", section: "OPERACIÓN", superadminOnly: false),
        .init(route: "/vendors", title: "Vendedores", symbol: "person.2.fill", section: "ADMINISTRACIÓN", superadminOnly: true),
        .init(route: "/vendors/create", title: "Nuevo vendedor", symbol: "person.badge.plus", section: "ADMINISTRACIÓN", superadminOnly: true),
        .init(route: "/precios", title: "Precios", symbol: "tag.fill", section: "ADMINISTRACIÓN", superadminOnly: true),
        .init(route: "/anuncio", title: "Anuncios", symbol: "megaphone.fill", section: "ADMINISTRACIÓN", superadminOnly: true),
        .init(route: "/app-builds", title: "Builds permitidos", symbol: "checkmark.shield.fill", section: "SISTEMA", superadminOnly: true),
        .init(route: "/maintenance", title: "Mantenimiento", symbol: "wrench.and.screwdriver.fill", section: "SISTEMA", superadminOnly: true),
        .init(route: "/tiempo", title: "Tiempos", symbol: "timer", section: "SISTEMA", superadminOnly: true),
        .init(route: "/hologramas", title: "Modos", symbol: "sparkles", section: "SISTEMA", superadminOnly: true),
        .init(route: "/avatarfiles", title: "Archivos", symbol: "photo.stack.fill", section: "SISTEMA", superadminOnly: true),
        .init(route: "/devices", title: "Dispositivos", symbol: "iphone.gen3", section: "SEGURIDAD", superadminOnly: true),
        .init(route: "/ips", title: "Direcciones IP", symbol: "network", section: "SEGURIDAD", superadminOnly: true),
        .init(route: "/sessions", title: "Sesiones", symbol: "person.crop.circle.badge.checkmark", section: "SEGURIDAD", superadminOnly: true),
        .init(route: "/bans", title: "Bloqueos", symbol: "hand.raised.fill", section: "SEGURIDAD", superadminOnly: true),
        .init(route: "/activity", title: "Actividad", symbol: "list.bullet.rectangle", section: "SEGURIDAD", superadminOnly: true),
        .init(route: "/health", title: "Salud del servicio", symbol: "heart.text.square.fill", section: "SEGURIDAD", superadminOnly: true)
    ]

    static let knownRoutes = Set(all.map(\.route))
}

enum AdminWorkerError: LocalizedError {
    case invalidCredentials
    case sessionExpired
    case forbidden
    case unsafeURL
    case uploadNotAvailable
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "No se pudo iniciar sesión. Revisa el usuario y la contraseña."
        case .sessionExpired: return "La sesión venció. Inicia sesión de nuevo."
        case .forbidden: return "Tu cuenta no tiene permiso para abrir esta sección."
        case .unsafeURL: return "El Worker rechazó una ruta no permitida."
        case .uploadNotAvailable: return "Esta pantalla requiere subir un archivo; esa acción aún no está habilitada en la interfaz nativa."
        case .http(let code): return "El Worker respondió con el error HTTP \(code)."
        case .invalidResponse: return "El Worker devolvió una respuesta que no se pudo interpretar."
        }
    }
}

private final class TrustedWorkerRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let host: String

    init(host: String) { self.host = host }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host.lowercased() else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class AdminWorkerClient {
    static let shared = AdminWorkerClient()

    private let baseURL = URL(string: "https://dz-holograma.davidporfirio17.workers.dev")!
    private let trustedHost = "dz.davidporfirio17.workers.dev"
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration, delegate: TrustedWorkerRedirectDelegate(host: trustedHost), delegateQueue: nil)
    }

    func restoreSession() async throws -> AdminPageModel {
        try await loadPage("/dashboard")
    }

    func login(username: String, password: String) async throws -> AdminPageModel {
        let pairs = [("u", username), ("p", password)]
        let result = try await perform(path: "/login", method: "POST", pairs: pairs)
        if result.page.isLoginPage || result.page.isForbidden {
            throw AdminWorkerError.invalidCredentials
        }
        let dashboard = try await loadPage("/dashboard")
        guard !dashboard.isLoginPage else { throw AdminWorkerError.invalidCredentials }
        return dashboard
    }

    func discoverRole() async -> AdminRole {
        do {
            let page = try await loadPage("/app-builds")
            return page.statusCode < 400 && !page.isLoginPage && !page.isForbidden ? .superadmin : .vendor
        } catch {
            return .vendor
        }
    }

    func loadPage(_ route: String) async throws -> AdminPageModel {
        let result = try await perform(path: route, method: "GET", pairs: [])
        if result.status == 401 { throw AdminWorkerError.sessionExpired }
        if result.status >= 500 { throw AdminWorkerError.http(result.status) }
        return result.page
    }

    func submit(form: AdminForm, values: [String: String]) async throws -> AdminPageModel {
        guard !form.requiresUpload else { throw AdminWorkerError.uploadNotAvailable }
        var pairs = form.hiddenFields.map { ($0.name, $0.value) }
        for field in form.fields {
            let value = values[field.id] ?? field.value
            if field.type == "checkbox" {
                if value == "true" { pairs.append((field.name, field.value.isEmpty ? "on" : field.value)) }
            } else if field.type == "radio" {
                if !value.isEmpty { pairs.append((field.name, value)) }
            } else {
                pairs.append((field.name, value))
            }
        }
        let result = try await perform(path: form.action, method: form.method, pairs: pairs)
        if result.status == 401 || result.page.isLoginPage { throw AdminWorkerError.sessionExpired }
        if result.status == 403 || result.page.isForbidden { throw AdminWorkerError.forbidden }
        if result.status >= 500 { throw AdminWorkerError.http(result.status) }
        return result.page
    }

    func logout() async {
        _ = try? await perform(path: "/logout", method: "GET", pairs: [])
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
    }

    private struct NetworkResult {
        let page: AdminPageModel
        let status: Int
    }

    private func perform(path: String, method: String, pairs: [(String, String)]) async throws -> NetworkResult {
        guard let url = safeURL(for: path) else { throw AdminWorkerError.unsafeURL }
        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased() == "GET" ? "GET" : "POST"
        request.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        if request.httpMethod == "POST" {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncoded(pairs).data(using: .utf8)
        } else if !pairs.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = (components.queryItems ?? []) + pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
            guard let queryURL = components.url else { throw AdminWorkerError.unsafeURL }
            request.url = queryURL
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = response.url else {
            throw AdminWorkerError.invalidResponse
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let page: AdminPageModel
        if contentType.contains("application/json"),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (object["message"] as? String)
                ?? (object["error"] as? String)
                ?? (object["status"] as? String)
                ?? "El Worker procesó la solicitud."
            page = AdminPageModel(
                route: finalURL.path,
                title: "Resultado",
                subtitle: nil,
                messages: [message],
                paragraphs: [],
                metrics: [],
                tables: [],
                forms: [],
                navigationRoutes: [],
                isLoginPage: false,
                isForbidden: http.statusCode == 403,
                statusCode: http.statusCode
            )
        } else {
            page = try AdminHTMLParser.parse(html, route: finalURL.path, baseURL: baseURL, statusCode: http.statusCode)
        }
        return NetworkResult(page: page, status: http.statusCode)
    }

    private func safeURL(for route: String) -> URL? {
        guard !route.hasPrefix("//"), let url = URL(string: route, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https", url.host?.lowercased() == trustedHost.lowercased() else { return nil }
        return url
    }

    private static func formEncoded(_ pairs: [(String, String)]) -> String {
        var components = URLComponents()
        components.queryItems = pairs.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.percentEncodedQuery ?? ""
    }
}

private enum AdminHTMLParser {
    static func parse(_ html: String, route: String, baseURL: URL, statusCode: Int) throws -> AdminPageModel {
        let document = try SwiftSoup.parse(html, baseURL.absoluteString)
        let bodyText = (try? document.body()?.text()) ?? ""
        let normalizedRoute = route.isEmpty ? "/" : route

        let title = firstText(document, selector: "h1")
            ?? firstText(document, selector: "h2")
            ?? (try? document.title())
            ?? AdminPageDefinition.all.first(where: { $0.route == normalizedRoute })?.title
            ?? "Nyxel Admin"
        let subtitle = firstText(document, selector: ".subtitle, .subtitulo, .lead, .page-description")
            ?? firstText(document, selector: "main > p, header p")
        let messages = uniqueTexts(document, selector: ".alert, [role=alert], .flash, .notice, .toast, .message", limit: 8)
        let paragraphs = uniqueTexts(document, selector: "main p, article p, .content p, p", limit: 12)
        let metrics = parseMetrics(document)
        let tables = parseTables(document)
        let forms = try parseForms(document, currentRoute: normalizedRoute, baseURL: baseURL)
        let navigationRoutes = parseNavigationRoutes(document)
        let lowerBody = bodyText.lowercased()
        let hasUserPasswordFields = ((try? document.select("input[name=u],input[name=p]").size()) ?? 0) > 0
        let hasPasswordField = ((try? document.select("input[type=password]").size()) ?? 0) > 0
        let loginPage = hasPasswordField && (hasUserPasswordFields || normalizedRoute == "/login")
        let forbidden = statusCode == 403 || ["acceso denegado", "no autorizado", "forbidden", "solo superadmin"].contains { lowerBody.contains($0) }

        return AdminPageModel(
            route: normalizedRoute,
            title: title,
            subtitle: subtitle,
            messages: messages,
            paragraphs: paragraphs,
            metrics: metrics,
            tables: tables,
            forms: forms,
            navigationRoutes: navigationRoutes,
            isLoginPage: loginPage,
            isForbidden: forbidden,
            statusCode: statusCode
        )
    }

    private static func firstText(_ document: Document, selector: String) -> String? {
        guard let element = try? document.select(selector).first() else { return nil }
        let text = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func uniqueTexts(_ document: Document, selector: String, limit: Int) -> [String] {
        guard let elements = try? document.select(selector) else { return [] }
        var output: [String] = []
        var seen = Set<String>()
        for element in elements {
            let value = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty, value.count < 600, seen.insert(value).inserted else { continue }
            output.append(value)
            if output.count >= limit { break }
        }
        return output
    }

    private static func parseMetrics(_ document: Document) -> [AdminMetric] {
        guard let elements = try? document.select(".stat-card, .metric-card, .kpi-card, .stat, .metric, [data-stat]") else { return [] }
        var output: [AdminMetric] = []
        var seen = Set<String>()
        for (index, element) in elements.enumerated() {
            let text = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty, text.count < 160, text.rangeOfCharacter(from: .decimalDigits) != nil, seen.insert(text).inserted else { continue }
            let valueElement = (try? element.select(".value, .stat-value, .metric-value, strong, b").first()) ?? nil
            let value = valueElement.flatMap { try? $0.text() }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = value.isEmpty ? text : text.replacingOccurrences(of: value, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            output.append(AdminMetric(id: "metric-\(index)", label: label.isEmpty ? "Resumen" : label, value: value.isEmpty ? text : value))
            if output.count == 8 { break }
        }
        return output
    }

    private static func parseTables(_ document: Document) -> [AdminTable] {
        guard let tableElements = try? document.select("table") else { return [] }
        var output: [AdminTable] = []
        for (tableIndex, table) in tableElements.enumerated() {
            let title = (try? table.select("caption").first()?.text()) ?? ""
            var headers: [String] = []
            if let headerElements = try? table.select("thead th") {
                for header in headerElements {
                    let text = (try? header.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !text.isEmpty { headers.append(text) }
                }
            }
            var rows: [[String]] = []
            guard let rowElements = try? table.select("tr") else { continue }
            for row in rowElements {
                guard let cells = try? row.select("td"), cells.size() > 0 else { continue }
                var values: [String] = []
                for cell in cells {
                    let text = (try? cell.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    values.append(text)
                }
                if values.contains(where: { !$0.isEmpty }) { rows.append(values) }
                if rows.count >= 100 { break }
            }
            if !rows.isEmpty || !headers.isEmpty {
                output.append(AdminTable(id: "table-\(tableIndex)", title: title, headers: headers, rows: rows))
            }
        }
        return output
    }

    private static func parseForms(_ document: Document, currentRoute: String, baseURL: URL) throws -> [AdminForm] {
        let formElements = try document.select("form")
        var output: [AdminForm] = []
        for (formIndex, form) in formElements.enumerated() {
            let rawAction = (try? form.attr("action")) ?? ""
            let action: String
            if rawAction.isEmpty {
                action = currentRoute
            } else {
                guard let resolvedAction = safeAction(rawAction, baseURL: baseURL) else { continue }
                action = resolvedAction
            }
            let method = ((try? form.attr("method")) ?? "GET").uppercased()
            let enctype = ((try? form.attr("enctype")) ?? "").lowercased()
            let upload = enctype.contains("multipart") || ((try? form.select("input[type=file]").size()) ?? 0) > 0
            var hidden: [AdminHiddenField] = []
            var fields: [AdminFormField] = []
            var processedRadioNames = Set<String>()
            var labelMap: [String: String] = [:]
            if let labels = try? document.select("label") {
                for label in labels {
                    let key = (try? label.attr("for")) ?? ""
                    let value = (try? label.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !key.isEmpty, !value.isEmpty { labelMap[key] = value }
                }
            }
            let controls = try form.select("input, select, textarea")
            for (fieldIndex, control) in controls.enumerated() {
                let tag = control.tagName().lowercased()
                let name = (try? control.attr("name")) ?? ""
                guard !name.isEmpty else { continue }
                let type = tag == "select" ? "select" : (tag == "textarea" ? "textarea" : ((try? control.attr("type")) ?? "text").lowercased())
                if ["submit", "button", "reset", "image"].contains(type) { continue }
                if type == "radio" {
                    guard processedRadioNames.insert(name).inserted,
                          let radioControls = try? form.select("input[type=radio][name='\(name)']") else { continue }
                    var radioOptions: [AdminFormOption] = []
                    var selectedRadioValue = ""
                    for (radioIndex, radio) in radioControls.enumerated() {
                        let radioValue = (try? radio.attr("value")) ?? ""
                        if radioValue.isEmpty { continue }
                        let radioTitle = labelMap[(try? radio.attr("id")) ?? ""] ?? humanize(radioValue)
                        radioOptions.append(AdminFormOption(id: "\(name)-radio-\(radioIndex)", title: radioTitle, value: radioValue))
                        if radio.hasAttr("checked") { selectedRadioValue = radioValue }
                    }
                    let radioID = (try? control.attr("id")) ?? ""
                    fields.append(AdminFormField(
                        id: "form-\(formIndex)-field-\(fieldIndex)",
                        name: name,
                        label: labelMap[radioID] ?? humanize(name),
                        type: "select",
                        value: selectedRadioValue,
                        placeholder: "",
                        required: control.hasAttr("required"),
                        options: radioOptions
                    ))
                    continue
                }
                let value: String
                if type == "checkbox" || type == "radio" {
                    value = (try? control.attr("value")) ?? "on"
                } else if tag == "textarea" {
                    value = (try? control.text()) ?? ""
                } else if tag == "select" {
                    value = selectedValue(control)
                } else {
                    value = (try? control.attr("value")) ?? ""
                }
                let id = (try? control.attr("id")) ?? ""
                let label = labelMap[id] ?? labelMap[name] ?? humanize(name)
                if type == "hidden" {
                    hidden.append(AdminHiddenField(name: name, value: value))
                    continue
                }
                var options: [AdminFormOption] = []
                if tag == "select" {
                    if let optionElements = try? control.select("option") {
                        for (optionIndex, option) in optionElements.enumerated() {
                            let optionValue = (try? option.attr("value")) ?? (try? option.text()) ?? ""
                            let optionTitle = (try? option.text()) ?? optionValue
                            if !optionValue.isEmpty { options.append(AdminFormOption(id: "\(name)-option-\(optionIndex)", title: optionTitle, value: optionValue)) }
                        }
                    }
                }
                let required = control.hasAttr("required")
                let placeholder = (try? control.attr("placeholder")) ?? ""
                fields.append(AdminFormField(
                    id: "form-\(formIndex)-field-\(fieldIndex)",
                    name: name,
                    label: label,
                    type: type,
                    value: type == "checkbox" ? (control.hasAttr("checked") ? "true" : "false") : value,
                    placeholder: placeholder,
                    required: required,
                    options: options
                ))
            }
            var submitTitle = "Enviar"
            if let button = try? form.select("button[type=submit], button:not([type]), input[type=submit]").first() {
                let buttonType = button.tagName().lowercased()
                submitTitle = buttonType == "input" ? (((try? button.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) : (((try? button.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                if submitTitle.isEmpty { submitTitle = "Enviar" }
            }
            let title = (try? form.select("legend, h2, h3, h4").first()?.text())?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? submitTitle
            let lower = "\(title) \(submitTitle) \(action)".lowercased()
            let confirmation = ["eliminar", "borrar", "delete", "revocar", "ban", "pausar", "kill", "permanente", "maintenance", "mantenimiento", "generate", "generar", "lote"].contains { lower.contains($0) }
            output.append(AdminForm(
                id: "form-\(formIndex)-\(action)",
                title: title,
                action: action,
                method: method,
                submitTitle: submitTitle,
                hiddenFields: hidden,
                fields: fields,
                requiresUpload: upload,
                needsConfirmation: confirmation
            ))
        }
        return output
    }

    private static func parseNavigationRoutes(_ document: Document) -> Set<String> {
        guard let links = try? document.select("a[href]") else { return [] }
        var routes = Set<String>()
        for link in links {
            let href = (try? link.attr("href")) ?? ""
            let parsedPath = URLComponents(string: href)?.path ?? ""
            let path = parsedPath.isEmpty ? href : parsedPath
            guard AdminPageDefinition.knownRoutes.contains(path) else { continue }
            routes.insert(path)
        }
        return routes
    }

    private static func safeAction(_ action: String, baseURL: URL) -> String? {
        guard let url = URL(string: action, relativeTo: baseURL)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == baseURL.host?.lowercased() else { return nil }
        return url.path + (url.query.map { "?\($0)" } ?? "")
    }

    private static func selectedValue(_ element: Element) -> String {
        guard let options = try? element.select("option") else { return "" }
        var fallback = ""
        for option in options {
            let value = (try? option.attr("value")) ?? ""
            let text = (try? option.text()) ?? ""
            let candidate = value.isEmpty ? text : value
            if fallback.isEmpty { fallback = candidate }
            if option.hasAttr("selected") { return candidate }
        }
        return fallback
    }

    private static func humanize(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
