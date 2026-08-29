import XCTest
@testable import Steady

@MainActor
final class ParsingTests: XCTestCase {
    func testParsePRsDerivesRepoFromURL() {
        let json = #"[{"number":77,"title":"Refactor","updatedAt":"2026-08-28T03:38:43Z","url":"https://github.com/owner/repo/pull/77"}]"#
        let prs = GitHubBridge.parsePRs(Data(json.utf8))
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs.first?.number, 77)
        XCTAssertEqual(prs.first?.repo, "owner/repo")
    }

    func testContributionStreaks() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int, _ count: Int) -> GHDay {
            GHDay(date: calendar.date(byAdding: .day, value: offset, to: today)!, count: count, colorHex: "1b1f24")
        }
        let week = [day(-4, 3), day(-3, 0), day(-2, 2), day(-1, 1), day(0, 4)]
        let contributions = GHContributions(total: 10, weeks: [week])
        XCTAssertEqual(contributions.currentStreak, 3)
        XCTAssertEqual(contributions.longestStreak, 3)
    }

    func testNotionParseMarkdownLink() {
        let text = "See [My Page](https://www.notion.so/My-Page-abc123) for details."
        let results = NotionProvider.parse(text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "My Page")
        XCTAssertEqual(results.first?.url, "https://www.notion.so/My-Page-abc123")
    }

    func testMailParseDelimited() {
        let unit = "\u{1F}"
        let record = "\u{1E}"
        let raw = "42\(unit)\"Bob\" <bob@example.com>\(unit)Hello there\(unit)27/08/2026\(unit)false\(record)"
        let messages = MailBridge.parseMessages(raw)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.senderName, "Bob")
        XCTAssertEqual(messages.first?.senderEmail, "bob@example.com")
        XCTAssertTrue(messages.first?.unread ?? false)
    }

    func testMonthGridIsWholeWeeks() {
        let days = CalendarFormat.monthGridDays(of: Date())
        XCTAssertEqual(days.count % 7, 0)
        XCTAssertGreaterThanOrEqual(days.count, 28)
    }

    func testTriageSnoozeExpires() {
        let triage = TriageCenter()
        triage.snooze("github", minutes: 60)
        XCTAssertTrue(triage.isSnoozed("github"))
        triage.clear("github")
        XCTAssertFalse(triage.isSnoozed("github"))
    }
}
