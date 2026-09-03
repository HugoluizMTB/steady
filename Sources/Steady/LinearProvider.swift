import Foundation
import AppKit

struct LinearIssue: Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let url: String
    let statusName: String
    let statusType: String
    let priority: Int
    let updatedAt: Date?
    let workspace: String
}

struct LinearConnection: Identifiable, Codable, Sendable {
    let id: String
    var label: String
    var needsReauth: Bool = false
}

struct LinearError: Error { let message: String }

@MainActor
@Observable
final class LinearProvider {
    enum Status: Equatable { case disconnected, authorizing, loading, ready, failed(String) }

    private(set) var status: Status = .disconnected
    private(set) var issues: [LinearIssue] = []
    private(set) var newIDs: Set<String> = []
    private(set) var connections: [LinearConnection] = []

    private let lastSeenKey = "linear.lastSeen"
    private let connectionsKey = "linear.connections"
    private let clientIdAccount = "linear.dcrClientId"
    private var loopback: OAuthLoopback?

    private static let authorizeEndpoint = "https://mcp.linear.app/authorize"
    private static let tokenEndpoint = URL(string: "https://mcp.linear.app/token")!
    private static let registerEndpoint = URL(string: "https://mcp.linear.app/register")!
    private static let mcpEndpoint = URL(string: "https://mcp.linear.app/mcp")!

    init() {
        migrateLegacy()
        connections = loadConnections()
    }

    var isConnected: Bool { !connections.isEmpty }

    private func tokenAccount(_ id: String) -> String { "linear.oauthToken.\(id)" }
    private func refreshAccount(_ id: String) -> String { "linear.refreshToken.\(id)" }

    func signIn() {
        status = .authorizing
        Task {
            do {
                let clientId = try await ensureClientId()
                beginAuthorization(clientId: clientId, reconnecting: nil)
            } catch let error as LinearError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func reconnect(_ id: String) {
        status = .authorizing
        Task {
            do {
                let clientId = try await ensureClientId()
                beginAuthorization(clientId: clientId, reconnecting: id)
            } catch let error as LinearError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect(_ id: String) {
        Keychain.delete(tokenAccount(id))
        Keychain.delete(refreshAccount(id))
        connections.removeAll { $0.id == id }
        saveConnections(connections)
        if connections.isEmpty {
            issues = []
            status = .disconnected
        } else {
            load()
        }
    }

    func load() {
        guard !connections.isEmpty else { status = .disconnected; return }
        status = .loading
        Task {
            var merged: [LinearIssue] = []
            for index in connections.indices {
                guard let fetched = await fetchWithRefresh(for: connections[index].id) else { continue }
                connections[index].needsReauth = false
                merged.append(contentsOf: fetched)
                if let workspace = fetched.first?.workspace, !workspace.isEmpty {
                    connections[index].label = workspace
                }
            }
            saveConnections(connections)

            if let previous = UserDefaults.standard.object(forKey: lastSeenKey) as? Double {
                let cutoff = Date(timeIntervalSince1970: previous)
                newIDs = Set(merged.filter { ($0.updatedAt ?? .distantPast) > cutoff }.map(\.id))
            } else {
                newIDs = []
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSeenKey)

            issues = merged
            status = .ready
        }
    }

    private func fetchWithRefresh(for id: String) async -> [LinearIssue]? {
        guard let token = Keychain.get(tokenAccount(id)) else { return nil }
        do {
            return try await Self.fetchAssigned(token: token)
        } catch let error as MCPError where error.isUnauthorized {
            guard let refreshed = await refreshedToken(for: id) else {
                markNeedsReauth(id)
                return nil
            }
            let retried = try? await Self.fetchAssigned(token: refreshed)
            if retried == nil { markNeedsReauth(id) }
            return retried
        } catch {
            return nil
        }
    }

    private func refreshedToken(for id: String) async -> String? {
        guard let refreshToken = Keychain.get(refreshAccount(id)),
              let clientId = Keychain.get(clientIdAccount),
              let pair = try? await Self.refreshAccessToken(refreshToken: refreshToken, clientId: clientId) else { return nil }
        Keychain.set(pair.access, for: tokenAccount(id))
        if let refresh = pair.refresh { Keychain.set(refresh, for: refreshAccount(id)) }
        return pair.access
    }

    private func markNeedsReauth(_ id: String) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].needsReauth = true
    }

    private func ensureClientId() async throws -> String {
        if let stored = Keychain.get(clientIdAccount) { return stored }
        let clientId = try await Self.registerClient(redirect: OAuthLoopback.redirectURI)
        Keychain.set(clientId, for: clientIdAccount)
        return clientId
    }

    private func beginAuthorization(clientId: String, reconnecting existingId: String?) {
        let verifier = PKCE.verifier()
        let challenge = PKCE.challenge(verifier)
        let state = PKCE.state()
        let redirect = OAuthLoopback.redirectURI

        let loopback = OAuthLoopback()
        self.loopback = loopback
        loopback.listen { [weak self] params in
            Task { @MainActor in
                guard let self else { return }
                guard let code = params?["code"], params?["state"] == state else {
                    self.status = .failed("Authorization was cancelled")
                    return
                }
                do {
                    let pair = try await Self.exchangeToken(code: code, verifier: verifier, clientId: clientId, redirect: redirect)
                    let id = existingId ?? UUID().uuidString
                    Keychain.set(pair.access, for: self.tokenAccount(id))
                    if let refresh = pair.refresh { Keychain.set(refresh, for: self.refreshAccount(id)) }
                    if let index = self.connections.firstIndex(where: { $0.id == id }) {
                        self.connections[index].needsReauth = false
                    } else {
                        self.connections.append(LinearConnection(id: id, label: "Workspace \(self.connections.count + 1)"))
                    }
                    self.saveConnections(self.connections)
                    self.load()
                } catch let error as LinearError {
                    self.status = .failed(error.message)
                } catch {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }

        var components = URLComponents(string: Self.authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "read"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    static func registerClient(redirect: String) async throws -> String {
        var request = URLRequest(url: registerEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "client_name": "Steady",
            "redirect_uris": [redirect],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
            "scope": "read",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else { throw LinearError(message: "Client registration failed (HTTP \(code))") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw LinearError(message: "Registration returned no client_id")
        }
        return clientId
    }

    static func exchangeToken(code: String, verifier: String, clientId: String, redirect: String) async throws -> OAuthTokenPair {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        request.httpBody = body.query?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LinearError(message: "Token exchange failed") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw LinearError(message: "No access token in response")
        }
        return OAuthTokenPair(access: token, refresh: json["refresh_token"] as? String)
    }

    static func refreshAccessToken(refreshToken: String, clientId: String) async throws -> OAuthTokenPair {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
        ]
        request.httpBody = body.query?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LinearError(message: "Token refresh failed") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw LinearError(message: "No access token in refresh response")
        }
        return OAuthTokenPair(access: token, refresh: json["refresh_token"] as? String ?? refreshToken)
    }

    static func fetchAssigned(token: String) async throws -> [LinearIssue] {
        let assigned = try await fetchIssues(token: token, arguments: ["assignee": "me", "limit": 50])
        if !assigned.isEmpty { return assigned }
        return (try? await fetchIssues(token: token, arguments: ["limit": 50])) ?? []
    }

    static func fetchIssues(token: String, arguments: [String: Any]) async throws -> [LinearIssue] {
        let result = try await MCP.call(endpoint: mcpEndpoint, token: token, method: "tools/call",
                                        params: ["name": "list_issues", "arguments": arguments])
        guard let text = MCP.toolText(result),
              let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let rawIssues = inner["issues"] as? [[String: Any]] else {
            throw LinearError(message: "No issues in response")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rawIssues.compactMap { issue -> LinearIssue? in
            guard let identifier = issue["id"] as? String else { return nil }
            var priority = 0
            if let object = issue["priority"] as? [String: Any] { priority = object["value"] as? Int ?? 0 }
            else if let value = issue["priority"] as? Int { priority = value }
            let url = issue["url"] as? String ?? ""
            return LinearIssue(
                id: identifier, identifier: identifier,
                title: issue["title"] as? String ?? "",
                url: url,
                statusName: issue["status"] as? String ?? "",
                statusType: issue["statusType"] as? String ?? "",
                priority: priority,
                updatedAt: (issue["updatedAt"] as? String).flatMap { iso.date(from: $0) },
                workspace: workspaceSlug(from: url))
        }
        .filter { $0.statusType != "completed" && $0.statusType != "canceled" }
    }

    private static func workspaceSlug(from url: String) -> String {
        (URLComponents(string: url)?.path ?? "").split(separator: "/").first.map(String.init) ?? ""
    }

    private func migrateLegacy() {
        guard loadConnections().isEmpty, let legacy = Keychain.get("linear.oauthToken") else { return }
        let id = UUID().uuidString
        Keychain.set(legacy, for: tokenAccount(id))
        Keychain.delete("linear.oauthToken")
        saveConnections([LinearConnection(id: id, label: "Workspace 1")])
    }

    private func loadConnections() -> [LinearConnection] {
        guard let data = UserDefaults.standard.data(forKey: connectionsKey),
              let decoded = try? JSONDecoder().decode([LinearConnection].self, from: data) else { return [] }
        return decoded
    }

    private func saveConnections(_ list: [LinearConnection]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: connectionsKey)
    }
}
