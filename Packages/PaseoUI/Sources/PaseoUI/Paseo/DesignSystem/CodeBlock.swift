import SwiftUI
import UIKit

/// Terminal-style output: an optional command line, then output that scrolls both ways inside a
/// capped height, so a 2,000-line log never takes over the conversation.
public struct CodeBlock: View {
    public enum Status: Sendable { case running, succeeded, failed, plain }

    var title: String?
    var command: String?
    var output: String?
    var status: Status
    var maxHeight: CGFloat

    public init(title: String? = nil, command: String? = nil, output: String?, status: Status = .plain, maxHeight: CGFloat = 260) {
        self.title = title
        self.command = command
        self.output = output
        self.status = status
        self.maxHeight = maxHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if command != nil || title != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    StatusDot(status: status)
                    if let title { Text(title).foregroundStyle(Palette.secondaryInk) }
                    if let command { Text(command).foregroundStyle(Palette.ink).lineLimit(3) }
                    Spacer(minLength: 8)
                    CopyButton(text: [command, output].compactMap { $0 }.joined(separator: "\n"))
                }
                .font(Typeset.mono)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                if hasOutput { Divider().overlay(Palette.hairline) }
            }
            if hasOutput, let output {
                ScrollView([.vertical, .horizontal]) {
                    Text(output)
                        .font(Typeset.monoSmall)
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var hasOutput: Bool { !(output ?? "").isEmpty }
}

public struct StatusDot: View {
    var status: CodeBlock.Status
    public init(status: CodeBlock.Status) { self.status = status }

    public var body: some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .succeeded: Circle().fill(Palette.success).frame(width: 7, height: 7)
        case .failed: Circle().fill(Palette.failure).frame(width: 7, height: 7)
        case .plain: EmptyView()
        }
    }
}

public struct CopyButton: View {
    var text: String
    @State private var copied = false
    public init(text: String) { self.text = text }

    public var body: some View {
        Button {
            UIPasteboard.general.string = text
            Haptics.selection()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Text(copied ? "Copied" : "Copy").font(Typeset.caption).foregroundStyle(Palette.secondaryInk)
        }
        .buttonStyle(.plain)
        .contentTransition(.opacity)
    }
}
