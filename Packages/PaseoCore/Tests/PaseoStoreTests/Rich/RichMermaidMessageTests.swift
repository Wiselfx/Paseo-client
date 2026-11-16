import Foundation
import Testing

@testable import PaseoStore

// V2.4: the diagram card shows mermaid's own failure text, one line, never WebKit's
// generic "A JavaScript exception occurred".
struct RichMermaidMessageTests {
    /// A real mermaid parse rejection is multi-line; the first useful line is the message.
    @Test func firstNonEmptyLineWins() {
        let raw = "\n  Parse error on line 2:\n  A --> B\n  ----^\nExpecting 'SEMI'"
        #expect(RichMermaidMessage.oneLine(raw) == "Parse error on line 2:")
    }

    /// Surrounding whitespace and trailing content are not part of the shown line.
    @Test func trimsTheChosenLine() {
        #expect(RichMermaidMessage.oneLine("  No diagram type detected  \nsecond") == "No diagram type detected")
    }

    /// Nothing useful: nil, so the card shows its own failure line instead of a blank.
    @Test func nothingUsefulIsNil() {
        #expect(RichMermaidMessage.oneLine("") == nil)
        #expect(RichMermaidMessage.oneLine("   \n\t\n") == nil)
    }

    /// A long renderer message is capped with an ellipsis, still one line.
    @Test func longMessagesAreCapped() throws {
        let raw = String(repeating: "x", count: 400) + "\nmore"
        let message = try #require(RichMermaidMessage.oneLine(raw, limit: 40))
        #expect(message.count == 41)
        #expect(message.hasSuffix("…"))
        #expect(!message.contains("\n"))
    }

    /// The generic WebKit sentence is a harness failure, not a diagram one; the renderer no
    /// longer sends it, and the card treats an empty renderer message as unavailable.
    @Test func genericWebKitSentenceIsNotAFallback() {
        #expect(RichMermaidMessage.oneLine("") == nil)
    }
}
