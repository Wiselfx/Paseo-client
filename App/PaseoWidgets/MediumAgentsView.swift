import SwiftUI
import WidgetKit

/// Up to 3 rows: status, title, project, relative time. Attention first.
struct MediumAgentsView: View {
    let snapshot: GlanceMirror?

    var body: some View {
        let agents = snapshot?.agents ?? []
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(agents.prefix(3))) { agent in
                AgentLink(agent) {
                    HStack(spacing: 8) {
                        AgentStatusMark(agent: agent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if let project = agent.project {
                                Text(project)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        if let updated = agent.updatedAt {
                            Text(updated, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer(minLength: 0)
            // One sentence per case, so a translation can reorder the host, the label
            // and the time.
            Group {
                if let snapshot {
                    if let host = snapshot.hostDisplayName {
                        Text("\(host) · Updated \(snapshot.capturedAt, style: .relative)")
                    } else {
                        Text("Updated \(snapshot.capturedAt, style: .relative)")
                    }
                } else {
                    Text("Updated")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
