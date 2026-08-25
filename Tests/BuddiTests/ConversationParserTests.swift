//
//  ConversationParserTests.swift
//  BuddiTests
//
//  First unit tests, covering the JSONL conversation parsing that broke
//  twice in review (string vs content-block messages). This folder is not
//  yet attached to an Xcode test target: add one via File > New > Target >
//  Unit Testing Bundle named BuddiTests, point it at Tests/BuddiTests, and
//  set the app as the host. Until then these compile nowhere and cost
//  nothing.
//

import XCTest
@testable import buddi

final class ConversationParserTests: XCTestCase {
    private func line(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func userLine(content: Any, timestamp: String = "2026-08-01T10:00:00.000Z") -> String {
        line([
            "type": "user",
            "timestamp": timestamp,
            "message": ["role": "user", "content": content],
        ])
    }

    func testTitleFromPlainStringMessage() async {
        let content = userLine(content: "fix the swipe direction")
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertEqual(info.firstUserMessage, "fix the swipe direction")
    }

    func testTitleFromContentBlocks() async {
        let content = userLine(content: [["type": "text", "text": "resolver el problema del swipe"]])
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertEqual(info.firstUserMessage, "resolver el problema del swipe")
    }

    func testCommandWrapperBlockIsSkippedForRealPrompt() async {
        let content = userLine(content: [
            ["type": "text", "text": "<command-name>/model</command-name>"],
            ["type": "text", "text": "refactor the parser"],
        ])
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertEqual(info.firstUserMessage, "refactor the parser")
    }

    func testToolResultMessagesProduceNoTitle() async {
        let content = userLine(content: [["type": "tool_result", "tool_use_id": "t1"]])
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertNil(info.firstUserMessage)
    }

    func testLastUserMessageDateFromContentBlocks() async {
        let content = userLine(
            content: [["type": "text", "text": "hola"]],
            timestamp: "2026-08-02T12:30:00.000Z"
        )
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertNotNil(info.lastUserMessageDate)
    }

    func testSystemReminderNeverBecomesTitle() async {
        let content = userLine(content: "<system-reminder>injected</system-reminder>")
        let info = await ConversationParser().parseContentForTesting(content)
        XCTAssertNil(info.firstUserMessage)
    }
}
