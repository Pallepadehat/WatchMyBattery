#!/usr/bin/env swift
// Turns one version's section of CHANGELOG.md into the release notes Sparkle shows in its update window.
//
//   swift scripts/release-notes.swift 0.3.3 < notes.md > build/appcast/WatchMyBattery.html
//
// release.sh pipes in the section it already cut out of the changelog. The result is an HTML fragment (no DOCTYPE or
// body), which generate_appcast embeds in the appcast entry, so the notes arrive with the update in one download and
// show even offline. Only the Markdown the changelog uses is understood: headings, paragraphs, bullets (one level of
// nesting), quotes, **bold**, *italic*, `code` and [links](url). The styling follows the system's, in light and dark.

import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/release-notes.swift <version> < notes.md\n".utf8))
    exit(2)
}
let version = CommandLine.arguments[1]
let markdown = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)

func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

/// Bold, italic, code and links, on text that's already escaped.
func inline(_ text: String) -> String {
    var html = escaped(text)
    let rules: [(pattern: String, template: String)] = [
        (#"`([^`]+)`"#, "<code>$1</code>"),
        (#"\[([^\]]+)\]\(([^)\s]+)\)"#, #"<a href="$2">$1</a>"#),
        (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
        (#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, "<em>$1</em>"),
    ]
    for rule in rules {
        html = html.replacingOccurrences(of: rule.pattern, with: rule.template, options: .regularExpression)
    }
    return html
}

var body: [String] = []
var paragraph: [String] = []
var quote: [String] = []
/// How many lists are open: the top level, and a nested one inside its last item. Each has its last item still open.
var listDepth = 0

func flushParagraph() {
    guard !paragraph.isEmpty else { return }
    // The first paragraph, before any heading, is the version's one-line summary.
    let isSummary = !body.contains { $0.hasPrefix("<h3") || $0.hasPrefix("<ul") }
    body.append(isSummary ? "<p class=\"summary\">\(inline(paragraph.joined(separator: " ")))</p>" : "<p>\(inline(paragraph.joined(separator: " ")))</p>")
    paragraph = []
}

func flushQuote() {
    guard !quote.isEmpty else { return }
    body.append("<blockquote>\(inline(quote.joined(separator: " ")))</blockquote>")
    quote = []
}

func closeLists(to depth: Int) {
    while listDepth > depth {
        body.append("</li></ul>")
        listDepth -= 1
    }
}

func flushAll() {
    flushParagraph()
    flushQuote()
    closeLists(to: 0)
}

for rawLine in markdown.components(separatedBy: .newlines) {
    let line = rawLine.trimmingCharacters(in: .whitespaces)
    let indent = rawLine.prefix { $0 == " " }.count

    if line.isEmpty {
        flushParagraph()
        flushQuote()
        continue
    }
    if line.hasPrefix("#") {
        flushAll()
        let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        body.append("<h3>\(inline(title))</h3>")
        continue
    }
    if line.hasPrefix("> ") || line == ">" {
        flushParagraph()
        closeLists(to: 0)
        quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
        continue
    }
    if line.hasPrefix("- ") || line.hasPrefix("* ") {
        flushParagraph()
        flushQuote()
        let item = inline(String(line.dropFirst(2)))
        let depth = indent >= 2 && listDepth >= 1 ? 2 : 1
        if depth > listDepth {
            // A nested list opens inside the item before it, which stays open around it.
            body.append("<ul>")
            listDepth = depth
        } else {
            // Back out of a nested list if this item isn't in it, then close the sibling before it.
            closeLists(to: depth)
            body.append("</li>")
        }
        body.append("<li>\(item)")
        continue
    }
    if listDepth > 0 && indent >= 2 {
        // A wrapped bullet: it carries on the item above.
        body[body.count - 1] += " " + inline(line)
        continue
    }
    closeLists(to: 0)
    flushQuote()
    paragraph.append(line)
}
flushAll()

let style = """
    <style>
    :root { color-scheme: light dark; }
    body { font: 13px/1.45 -apple-system, system-ui, sans-serif; -webkit-font-smoothing: antialiased; }
    .notes { padding: 2px 4px 8px; }
    .notes h2 { font-size: 17px; font-weight: 700; letter-spacing: -0.01em; margin: 0 0 2px; }
    .notes .summary { color: #6e6e73; margin: 0 0 4px; }
    .notes h3 { font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: #6e6e73; margin: 16px 0 6px; }
    .notes ul { margin: 0; padding-left: 20px; }
    .notes ul ul { margin-top: 4px; }
    .notes li { margin: 0 0 7px; }
    .notes li::marker { color: #8e8e93; }
    .notes p { margin: 8px 0; }
    .notes a { color: #0066cc; text-decoration: none; }
    .notes a:hover { text-decoration: underline; }
    .notes code { font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; padding: 1px 4px; border-radius: 4px; background: rgba(0, 0, 0, 0.06); }
    .notes blockquote { margin: 12px 0 0; padding: 8px 12px; border-radius: 8px; background: rgba(0, 0, 0, 0.05); color: #6e6e73; }
    @media (prefers-color-scheme: dark) {
      .notes .summary, .notes h3, .notes blockquote { color: #a1a1a6; }
      .notes a { color: #4aa3ff; }
      .notes code, .notes blockquote { background: rgba(255, 255, 255, 0.08); }
    }
    </style>
    """

print(style)
print("<div class=\"notes\">")
print("<h2>WatchMyBattery \(escaped(version))</h2>")
print(body.joined(separator: "\n"))
print("</div>")
