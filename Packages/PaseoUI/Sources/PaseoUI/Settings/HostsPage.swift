#if canImport(UIKit)
import SwiftUI
import UIKit

/// Settings → Hosts: every daemon this device knows, with forget/rename. Switching lives on the
/// sidebar footer; this page is the manage surface. Data comes from the app-injected
/// `HostSwitchContext`; in a context of nil the page renders as empty.
struct HostsPage: View {
    @Environment(\.hostSwitch) private var context

    @State private var renameTarget: HostSwitchEntry?
    @State private var renameText = ""
    @State private var forgetTarget: HostSwitchEntry?

    private let typography = ClaudeTypography()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("Saved hosts")
                if hosts.isEmpty {
                    RowGroup {
                        Text("No saved hosts yet. Every successful connection is remembered here, with its password kept in this device's Keychain.")
                            .font(.system(size: 15))
                            .foregroundStyle(ClaudePalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(minHeight: 52, alignment: .leading)
                    }
                } else {
                    RowGroup {
                        ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                            hostRow(host)
                            if index < hosts.count - 1 { rowDivider }
                        }
                    }
                }
                Text("Passwords are stored per host in this device's Keychain, never in plain settings. Forgetting a host removes its password too.")
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudePalette.secondary)
                    .padding(.leading, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $renameTarget) { target in renameSheet(target) }
        .confirmationDialog(
            "Forget \(forgetTarget?.label ?? "this host")?",
            isPresented: Binding(
                get: { forgetTarget != nil }, set: { if !$0 { forgetTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Forget host", role: .destructive) {
                if let id = forgetTarget?.id { context?.forgetHost(id) }
                forgetTarget = nil
            }
            Button("Cancel", role: .cancel) { forgetTarget = nil }
        } message: {
            Text("The password stored on this device for this host is removed too. The daemon itself is not changed.")
        }
    }

    private var hosts: [HostSwitchEntry] { context?.hosts ?? [] }

    private func hostRow(_ host: HostSwitchEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(host.label)
                        .font(.system(size: 17))
                        .lineLimit(1)
                    if host.isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ClaudePalette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(ClaudePalette.chip, in: .capsule)
                    }
                }
                Text(host.urlLine)
                    .font(typography.mono(12, relativeTo: .footnote))
                    .foregroundStyle(ClaudePalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let lastConnectedAt = host.lastConnectedAt {
                    Text(
                        host.isCurrent
                            ? "Connected now"
                            : "Last connected \(Self.relative(lastConnectedAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.captionInk)
                } else {
                    Text("Never connected on this device")
                        .font(.system(size: 12))
                        .foregroundStyle(ClaudePalette.captionInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Haptics.selection()
                renameText = host.label
                renameTarget = host
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 17, weight: .light))
                    .frame(width: 38, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(host.label)")
            .accessibilityIdentifier("settings.hosts.rename.\(host.id.uuidString)")
            Button {
                Haptics.selection()
                forgetTarget = host
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(ClaudePalette.failureInk)
                    .frame(width: 38, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forget \(host.label)")
            .accessibilityIdentifier("settings.hosts.forget.\(host.id.uuidString)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 56)
    }

    private func renameSheet(_ target: HostSwitchEntry) -> some View {
        VStack(spacing: 16) {
            SheetHeader(title: "Rename host", close: { renameTarget = nil })
            RowGroup {
                TextField("Label", text: $renameText)
                    .font(typography.sans(17))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { saveRename(target) }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .accessibilityIdentifier("settings.hosts.rename.field")
            }
            Button {
                saveRename(target)
            } label: {
                Text("Save")
                    .font(typography.sans(16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(ClaudePalette.background)
                    .background(ClaudePalette.ink, in: .capsule)
                    .opacity(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("settings.hosts.rename.save")
            Spacer(minLength: 0)
        }
        .background(ClaudePalette.background)
        .foregroundStyle(ClaudePalette.ink)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(38)
    }

    private func saveRename(_ target: HostSwitchEntry) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptics.selection()
        context?.renameHost(target.id, trimmed)
        renameTarget = nil
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 16).padding(.trailing, 16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15))
            .foregroundStyle(ClaudePalette.secondary)
            .padding(.leading, 16)
            .padding(.top, 8)
            .padding(.bottom, -8)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        let days = seconds / 86400
        return days == 1 ? "yesterday" : "\(days)d ago"
    }
}
#endif
