import Foundation
import Network

final class OAuthLoopback {
    static let port: UInt16 = 33418
    static var redirectURI: String { "http://localhost:\(port)/callback" }

    private var listener: NWListener?

    func listen(_ completion: @escaping ([String: String]?) -> Void) {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let params = Self.parseQuery(request)
                    let page = "<html><body style=\"font-family:-apple-system;background:#07090b;color:#f4f6f8;text-align:center;padding-top:90px\"><h2>Steady is connected ✓</h2><p style=\"color:#8f9299\">You can close this tab and return to Steady.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                    connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    self?.stop()
                    completion(params.isEmpty ? nil : params)
                }
            }
            listener.start(queue: .global())
        } catch {
            completion(nil)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func parseQuery(_ request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n").first else { return [:] }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let query = parts[1].split(separator: "?").dropFirst().first else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }
        return result
    }
}
