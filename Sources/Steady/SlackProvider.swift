import Foundation
import AppKit

struct SlackError: Error { let message: String }

@MainActor
@Observable
final class SlackProvider {
    enum Status: Equatable { case disconnected, authorizing, loading, ready, failed(String) }

    private(set) var status: Status = .disconnected
    private(set) var toolCount = 0

    private let tokenAccount = "slack.token"
    private let clientIdAccount = "slack.clientId"
    private let clientSecretAccount = "slack.clientSecret"
    private var loopback: OAuthLoopback?

    private static let mcpEndpoint = URL(string: "https://mcp.slack.com/mcp")!
    private static let authorizeEndpoint = "https://slack.com/oauth/v2_user/authorize"
    private static let tokenEndpoint = URL(string: "https://slack.com/api/oauth.v2.user.access")!
    private let scope = "channels:history,channels:read,groups:history,im:history,mpim:history,users:read,search:read.public,search:read.im,search:read.mpim,chat:write"

    var isConnected: Bool { Keychain.get(tokenAccount) != nil }
    var savedClientId: String { Keychain.get(clientIdAccount) ?? "" }
    var savedClientSecret: String { Keychain.get(clientSecretAccount) ?? "" }

    func authorize(clientId: String, clientSecret: String) {
        let id = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return }
        Keychain.set(id, for: clientIdAccount)
        Keychain.set(secret, for: clientSecretAccount)

        status = .authorizing
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
                    let token = try await Self.exchangeToken(code: code, verifier: verifier, clientId: id, clientSecret: secret, redirect: redirect)
                    Keychain.set(token, for: self.tokenAccount)
                    self.load()
                } catch let error as SlackError {
                    self.status = .failed(error.message)
                } catch {
                    self.status = .failed(error.localizedDescription)
                }
            }
        }

        var components = URLComponents(string: Self.authorizeEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    func disconnect() {
        loopback?.stop()
        Keychain.delete(tokenAccount)
        status = .disconnected
    }

    func load() {
        guard let token = Keychain.get(tokenAccount) else { status = .disconnected; return }
        status = .loading
        Task {
            do {
                let result = try await MCP.call(endpoint: Self.mcpEndpoint, token: token, method: "tools/list", params: [:])
                toolCount = (result["tools"] as? [[String: Any]])?.count ?? 0
                status = .ready
            } catch let error as MCPError {
                status = .failed(error.message)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    static func exchangeToken(code: String, verifier: String, clientId: String, clientSecret: String, redirect: String) async throws -> String {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "code_verifier", value: verifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
        ]
        request.httpBody = body.query?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError(message: "Unexpected response from Slack")
        }
        if (json["ok"] as? Bool) != true {
            throw SlackError(message: (json["error"] as? String) ?? "Slack authorization failed")
        }
        if let authed = json["authed_user"] as? [String: Any], let token = authed["access_token"] as? String {
            return token
        }
        if let token = json["access_token"] as? String {
            return token
        }
        throw SlackError(message: "No access token in Slack response")
    }
}
