import Foundation
import CryptoKit
import Security

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func state() -> String { UUID().uuidString }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum MCP {
    static func call(endpoint: URL, token: String, method: String, params: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw MCPError(message: code == 401 ? "Session expired. Sign in again" : "MCP returned HTTP \(code)", status: code)
        }
        let body = String(decoding: data, as: UTF8.self)
        let payload = body.split(separator: "\n")
            .filter { $0.hasPrefix("data:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
            .joined()
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw MCPError(message: "Unexpected MCP response")
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            throw MCPError(message: message)
        }
        return (json["result"] as? [String: Any]) ?? [:]
    }

    static func toolText(_ result: [String: Any]) -> String? {
        (result["content"] as? [[String: Any]])?.first?["text"] as? String
    }
}

struct MCPError: Error {
    let message: String
    var status: Int? = nil
    var isUnauthorized: Bool { status == 401 }
}

struct OAuthTokenPair: Sendable {
    let access: String
    let refresh: String?
}
