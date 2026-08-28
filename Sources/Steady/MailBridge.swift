import Foundation

struct MailMessage: Identifiable, Sendable, Hashable {
    let id: Int
    let senderName: String
    let senderEmail: String
    let subject: String
    let dateText: String
    let unread: Bool
}

enum MailBridge {
    struct RunResult: Sendable {
        let output: String
        let stderr: String
        let ok: Bool

        var authDenied: Bool {
            stderr.contains("-1743")
                || stderr.localizedCaseInsensitiveContains("not authoriz")
                || stderr.localizedCaseInsensitiveContains("not allowed to send")
        }
    }

    static func accounts() -> RunResult { run(accountsScript) }
    static func recent(limit: Int) -> RunResult { run(recentScript(limit)) }
    static func body(id: Int) -> RunResult { run(bodyScript, [String(id)]) }
    static func markRead(id: Int) -> RunResult { run(markReadScript, [String(id)]) }
    static func send(to: String, subject: String, body: String) -> RunResult { run(sendScript, [to, subject, body]) }

    static func parseAccounts(_ output: String) -> [String] {
        output.components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseMessages(_ output: String) -> [MailMessage] {
        output.components(separatedBy: "\u{1E}").compactMap { record in
            let fields = record.components(separatedBy: "\u{1F}")
            guard fields.count >= 5, let id = Int(fields[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let sender = splitSender(fields[1])
            return MailMessage(
                id: id,
                senderName: sender.name,
                senderEmail: sender.email,
                subject: fields[2].trimmingCharacters(in: .whitespacesAndNewlines),
                dateText: fields[3].trimmingCharacters(in: .whitespacesAndNewlines),
                unread: fields[4].trimmingCharacters(in: .whitespaces).lowercased() == "false"
            )
        }
    }

    private static func splitSender(_ raw: String) -> (name: String, email: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.range(of: "<"), let close = trimmed.range(of: ">"), open.upperBound <= close.lowerBound else {
            return (trimmed, trimmed)
        }
        let email = String(trimmed[open.upperBound..<close.lowerBound])
        let name = String(trimmed[..<open.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (name.isEmpty ? email : name, email)
    }

    private static func run(_ script: String, _ args: [String] = []) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"] + args
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            input.fileHandleForWriting.write(Data(script.utf8))
            input.fileHandleForWriting.closeFile()
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            let errData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return RunResult(
                output: String(decoding: outData, as: UTF8.self),
                stderr: String(decoding: errData, as: UTF8.self),
                ok: process.terminationStatus == 0
            )
        } catch {
            return RunResult(output: "", stderr: error.localizedDescription, ok: false)
        }
    }

    private static let accountsScript = """
    tell application "Mail"
        set _us to character id 31
        set _out to ""
        repeat with _a in accounts
            try
                if enabled of _a then set _out to _out & (get item 1 of (email addresses of _a)) & _us
            end try
        end repeat
        return _out
    end tell
    """

    private static func recentScript(_ limit: Int) -> String {
        """
        set _lim to \(limit)
        tell application "Mail"
            set _box to inbox
            set _n to count of messages of _box
            if _n < _lim then set _lim to _n
            set _us to character id 31
            set _rs to character id 30
            set _out to ""
            repeat with _i from 1 to _lim
                set _m to message _i of _box
                try
                    set _out to _out & (id of _m as string) & _us & (sender of _m) & _us & (subject of _m) & _us & (short date string of (date received of _m)) & _us & (read status of _m as string) & _rs
                end try
            end repeat
            return _out
        end tell
        """
    }

    private static let bodyScript = """
    on run argv
        set _id to (item 1 of argv) as integer
        tell application "Mail"
            set _matches to (messages of inbox whose id is _id)
            if (count of _matches) is 0 then return ""
            return content of item 1 of _matches
        end tell
    end run
    """

    private static let markReadScript = """
    on run argv
        set _id to (item 1 of argv) as integer
        tell application "Mail"
            set _matches to (messages of inbox whose id is _id)
            if (count of _matches) > 0 then set read status of item 1 of _matches to true
        end tell
    end run
    """

    private static let sendScript = """
    on run argv
        set _to to item 1 of argv
        set _subj to item 2 of argv
        set _body to item 3 of argv
        tell application "Mail"
            set _msg to make new outgoing message with properties {subject:_subj, content:_body, visible:false}
            tell _msg
                make new to recipient at end of to recipients with properties {address:_to}
                send
            end tell
        end tell
    end run
    """
}
