//
//  DisplayText.swift
//  Buddi
//
//  Turns raw transcript text into something fit for a one-line notch label.
//  Transcripts carry injected XML blocks (<system-reminder>,
//  <browser_instruction>, <command-name>, ...) and markdown (# headings,
//  **bold**, `code`, list bullets) that read as noise in a popup or a row.
//

import Foundation

enum DisplayText {
    private static let tagBlock = try! NSRegularExpression(
        pattern: "<([A-Za-z_][\\w-]*)(?:\\s[^>]*)?>.*?</\\1>",
        options: [.dotMatchesLineSeparators]
    )
    private static let strayTag = try! NSRegularExpression(
        pattern: "</?[A-Za-z_][\\w-]*(?:\\s[^>]*)?/?>"
    )
    private static let lineMarkup = try! NSRegularExpression(
        pattern: "^\\s*(?:#{1,6}\\s+|>\\s?|[-*+]\\s+|\\d+\\.\\s+)",
        options: [.anchorsMatchLines]
    )
    private static let inlineMarkup = try! NSRegularExpression(
        pattern: "\\*\\*|__|`+|\\*(?=\\S)|(?<=\\S)\\*"
    )
    private static let mdLink = try! NSRegularExpression(
        pattern: "\\[([^\\]]+)\\]\\([^)]*\\)"
    )
    private static let whitespace = try! NSRegularExpression(pattern: "\\s+")

    /// Clean display text, or nil when nothing human-readable remains.
    static func clean(_ raw: String?) -> String? {
        guard var text = raw, !text.isEmpty else { return nil }
        text = replace(tagBlock, in: text, with: " ")
        text = replace(strayTag, in: text, with: " ")
        text = replace(mdLink, in: text, with: "$1")
        text = replace(lineMarkup, in: text, with: "")
        text = replace(inlineMarkup, in: text, with: "")
        text = replace(whitespace, in: text, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
