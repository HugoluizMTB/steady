import Foundation
import AppKit

struct NotionResult: Identifiable, Sendable {
    let id: String
    let title: String
    let url: String
    let snippet: String
}

struct NotionError: Error { let message: String }

@MainActor
@Observable
final class NotionProvider {
    enum Status: Equatable { case disconnected, authorizing, loading, ready, failed(String) }

    private(set) var status: Status = .disconnected
    private(set) var results: [NotionResult] = []
    private(set) var rawText = ""
    private(set) var query = ""

    private let tokenAccount = "notion.oauthToken"
    private let refreshTokenAccount = "notion.refreshToken"
    private let clientIdAccount = "notion.dcrClientId"
    private var loopback: OAuthLoopback?

    private static let authorizeEndpoint = "https://mcp.notion.com/authorize"
    private static let tokenEndpoint = URL(string: "https://mcp.notion.com/token")!
    private static let registerEndpoint = URL(string: "https://mcp.notion.com/register")!
    private static let mcpEndpoint = URL(string: "https://mcp.notion.com/mcp")!

    var isConnected: Bool { Keychain.get(tokenAccount) != nil }

    func signIn() {
        status = .authorizing
        Task {
            do {
                let clientId = try await ensureClientId()
                beginAuthorization(clientId: clientId)
            } catch let error as NotionError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func disconnect() {
        loopback?.stop()
        Keychain.delete(tokenAccount)
        Keychain.delete(refreshTokenAccount)
        results = []
        rawText = ""
        status = .disconnected
    }

    func load() {
        guard isConnected else { status = .disconnected; return }
        search(query)
    }

    func search(_ text: String) {
        guard let token = Keychain.get(tokenAccount) else { status = .disconnected; return }
        query = text
        status = .loading
        Task {
            do {
                results = try await runSearch(text, token: token)
                status = .ready
            } catch let error as MCPError where error.isUnauthorized {
                await retryAfterRefresh(text)
            } catch let error as MCPError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func runSearch(_ text: String, token: String) async throws -> [NotionResult] {
        let result = try await MCP.call(
            endpoint: Self.mcpEndpoint, token: token, method: "tools/call",
            params: ["name": "notion-search", "arguments": ["query": text]]
        )
        let raw = MCP.toolText(result) ?? ""
        rawText = raw
        return Self.parse(raw)
    }

    private func retryAfterRefresh(_ text: String) async {
        guard let refreshToken = Keychain.get(refreshTokenAccount),
              let clientId = Keychain.get(clientIdAccount),
              let pair = try? await Self.refreshAccessToken(refreshToken: refreshToken, clientId: clientId) else {
            status = .failed("Session expired. Sign in again")
            return
        }
        Keychain.set(pair.access, for: tokenAccount)
        if let refresh = pair.refresh { Keychain.set(refresh, for: refreshTokenAccount) }
        do {
            results = try await runSearch(text, token: pair.access)
            status = .ready
        } catch {
            status = .failed("Session expired. Sign in again")
        }
    }

    private func ensureClientId() async throws -> String {
        if let stored = Keychain.get(clientIdAccount) { return stored }
        let clientId = try await Self.registerClient(redirect: OAuthLoopback.redirectURI)
        Keychain.set(clientId, for: clientIdAccount)
        return clientId
    }

    private func beginAuthorization(clientId: String) {
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
                    Keychain.set(pair.access, for: self.tokenAccount)
                    if let refresh = pair.refresh { Keychain.set(refresh, for: self.refreshTokenAccount) }
                    self.load()
                } catch let error as NotionError {
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
            URLQueryItem(name: "scope", value: "default"),
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
            "scope": "default",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 201 else { throw NotionError(message: "Client registration failed (HTTP \(code))") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientId = json["client_id"] as? String else {
            throw NotionError(message: "Registration returned no client_id")
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NotionError(message: "Token exchange failed") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NotionError(message: "No access token in response")
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NotionError(message: "Token refresh failed") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw NotionError(message: "No access token in refresh response")
        }
        return OAuthTokenPair(access: token, refresh: json["refresh_token"] as? String ?? refreshToken)
    }

    static func parse(_ text: String) -> [NotionResult] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) {
            let items = (object as? [String: Any])?["results"] as? [[String: Any]] ?? object as? [[String: Any]] ?? []
            let parsed = items.compactMap(parseItem)
            if !parsed.isEmpty { return parsed }
        }

        if let markdown = extract(trimmed, pattern: "\\[([^\\]]{1,200})\\]\\((https?://[^)\\s]+)\\)", titleGroup: 1, urlGroup: 2), !markdown.isEmpty {
            return markdown
        }

        return extract(trimmed, pattern: "https?://(?:www\\.)?notion\\.so/[^\\s)\"']+", titleGroup: 0, urlGroup: 0) ?? []
    }

    private static func parseItem(_ item: [String: Any]) -> NotionResult? {
        let url = item["url"] as? String ?? item["public_url"] as? String ?? ""
        var title = item["title"] as? String ?? item["name"] as? String ?? ""
        if title.isEmpty, !url.isEmpty { title = prettyTitle(url) }
        guard !url.isEmpty || !title.isEmpty else { return nil }
        let id = item["id"] as? String ?? (url.isEmpty ? title : url)
        let snippet = item["snippet"] as? String ?? item["description"] as? String ?? ""
        return NotionResult(id: id, title: title.isEmpty ? "(untitled)" : title, url: url, snippet: snippet)
    }

    private static func extract(_ text: String, pattern: String, titleGroup: Int, urlGroup: Int) -> [NotionResult]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let string = text as NSString
        var out: [NotionResult] = []
        var seen = Set<String>()
        for match in regex.matches(in: text, range: range) where match.numberOfRanges > max(titleGroup, urlGroup) {
            let url = string.substring(with: match.range(at: urlGroup))
            let title = titleGroup == urlGroup ? prettyTitle(url) : string.substring(with: match.range(at: titleGroup))
            if seen.insert(url).inserted { out.append(NotionResult(id: url, title: title, url: url, snippet: "")) }
        }
        return out
    }

    private static func prettyTitle(_ url: String) -> String {
        let slug = url.split(separator: "/").last.map(String.init) ?? url
        let withoutID = slug.split(separator: "-").dropLast().joined(separator: " ")
        let cleaned = (withoutID.isEmpty ? slug : withoutID).removingPercentEncoding ?? slug
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}
