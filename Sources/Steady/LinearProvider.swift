import Foundation
import AppKit
import CryptoKit
import Security

struct LinearIssue: Identifiable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let url: String
    let statusName: String
    let statusType: String
    let priority: Int
    let updatedAt: Date?
}

struct LinearError: Error { let message: String }

@MainActor
@Observable
final class LinearProvider {
    enum Status: Equatable { case disconnected, authorizing, loading, ready, failed(String) }

    private(set) var status: Status = .disconnected
    private(set) var issues: [LinearIssue] = []
    private(set) var newIDs: Set<String> = []
    private let lastSeenKey = "linear.lastSeen"

    private let tokenAccount = "linear.oauthToken"
    private let clientIdAccount = "linear.dcrClientId"
    private var loopback: OAuthLoopback?

    private static let authorizeEndpoint = "https://mcp.linear.app/authorize"
    private static let tokenEndpoint = URL(string: "https://mcp.linear.app/token")!
    private static let registerEndpoint = URL(string: "https://mcp.linear.app/register")!

    var isConnected: Bool { Keychain.get(tokenAccount) != nil }

    func signIn() {
        status = .authorizing
        Task {
            do {
                let clientId = try await ensureClientId()
                beginAuthorization(clientId: clientId)
            } catch let error as LinearError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        loopback?.stop()
        Keychain.delete(tokenAccount)
        issues = []
        status = .disconnected
    }

    func load() {
        guard let token = Keychain.get(tokenAccount) else { status = .disconnected; return }
        status = .loading
        Task {
            do {
                let fetched = try await Self.fetchAssigned(token: token)
                if let previous = UserDefaults.standard.object(forKey: lastSeenKey) as? Double {
                    let cutoff = Date(timeIntervalSince1970: previous)
                    newIDs = Set(fetched.filter { ($0.updatedAt ?? .distantPast) > cutoff }.map(\.id))
                } else {
                    newIDs = []
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSeenKey)
                issues = fetched
                status = .ready
            } catch let error as LinearError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func ensureClientId() async throws -> String {
        if let stored = Keychain.get(clientIdAccount) { return stored }
        let clientId = try await Self.registerClient(redirect: OAuthLoopback.redirectURI)
        Keychain.set(clientId, for: clientIdAccount)
        return clientId
    }

    private func beginAuthorization(clientId: String) {
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        let state = UUID().uuidString
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
                    let token = try await Self.exchangeToken(code: code, verifier: verifier, clientId: clientId, redirect: redirect)
                    Keychain.set(token, for: self.tokenAccount)
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
        guard code == 200 || code == 201 else {
            throw LinearError(message: "Client registration failed (HTTP \(code))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw LinearError(message: "Registration returned no client_id")
        }
        return clientId
    }

    static func exchangeToken(code: String, verifier: String, clientId: String, redirect: String) async throws -> String {
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LinearError(message: "Token exchange failed")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw LinearError(message: "No access token in response")
        }
        return token
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static let mcpEndpoint = URL(string: "https://mcp.linear.app/mcp")!

    static func fetchAssigned(token: String) async throws -> [LinearIssue] {
        var request = URLRequest(url: mcpEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let payload: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": "list_issues", "arguments": ["assignee": "me", "limit": 50]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LinearError(message: "No response") }
        guard http.statusCode == 200 else {
            throw LinearError(message: http.statusCode == 401 ? "Session expired — sign in again" : "Linear MCP returned HTTP \(http.statusCode)")
        }

        let body = String(decoding: data, as: UTF8.self)
        let dataPayload = body.split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            .joined()
        guard let outer = try? JSONSerialization.jsonObject(with: Data(dataPayload.utf8)) as? [String: Any] else {
            throw LinearError(message: "Unexpected MCP response")
        }
        if let error = outer["error"] as? [String: Any], let message = error["message"] as? String {
            throw LinearError(message: message)
        }
        guard let result = outer["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let issues = inner["issues"] as? [[String: Any]] else {
            throw LinearError(message: "No issues in response")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return issues.compactMap { issue -> LinearIssue? in
            guard let identifier = issue["id"] as? String else { return nil }
            var priority = 0
            if let object = issue["priority"] as? [String: Any] { priority = object["value"] as? Int ?? 0 }
            else if let value = issue["priority"] as? Int { priority = value }
            return LinearIssue(
                id: identifier, identifier: identifier,
                title: issue["title"] as? String ?? "",
                url: issue["url"] as? String ?? "",
                statusName: issue["status"] as? String ?? "",
                statusType: issue["statusType"] as? String ?? "",
                priority: priority,
                updatedAt: (issue["updatedAt"] as? String).flatMap { iso.date(from: $0) })
        }
        .filter { $0.statusType != "completed" && $0.statusType != "canceled" }
    }
}
