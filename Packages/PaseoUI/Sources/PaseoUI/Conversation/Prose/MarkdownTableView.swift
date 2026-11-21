#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// One table (Phase C §9.1): horizontal scroll inside the block, a pinned label column when the
/// table earns it, header tap to full screen. Rows append downward with stable ids; widths
/// come from the plan cache and only ever grow.
///
/// The table owns its state: the viewport width it measured, its content width (the overflow
/// signal) and its full-screen sheet. A width change or an expansion therefore re-renders this
/// table only, never the rest of the document, and two tables can never read each other's
/// widths or present each other's sheet. Only a table reads the viewport, so plain prose mounts
/// no geometry reader (W8).
///
/// Equatable on its value inputs, like `ClaudeMarkdownView`: a settled table is skipped when the
/// document re-renders.
struct MarkdownTableView: View, Equatable {
    nonisolated static func == (lhs: MarkdownTableView, rhs: MarkdownTableView) -> Bool {
        // Statements, not one `&&` chain: `theme` is main-actor isolated and an autoclosure is not.
        guard lhs.path == rhs.path, lhs.contentVersion == rhs.contentVersion else { return false }
        guard lhs.theme == rhs.theme else { return false }
        guard lhs.alignments == rhs.alignments, lhs.header == rhs.header else { return false }
        return lhs.rows == rhs.rows
    }

    let header: [[MarkdownInline]]
    let rows: [[[MarkdownInline]]]
    let alignments: [MarkdownColumnAlignment]
    /// The table's document-unique path (`String.markdownChild`): it keeps same-header tables apart
    /// in the plan cache, nested ones included.
    let path: String
    /// The table's content version from `MarkdownDocumentModel.tableVersions`.
    let contentVersion: Int
    let theme: ClaudeMarkdownTheme

    /// The width this table is offered: the overflow and pin decisions compare against it.
    @State private var viewport: CGFloat = 0
    /// The table's content width: the overflow signal. Written only when it changes, never per
    /// scroll frame.
    @State private var contentWidth: CGFloat = 0
    @State private var isExpanded = false

    var body: some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        let key = planKey
        let plan = MarkdownTablePlanCache.lookup(key: key)
        let firstCells = rows.map { $0.first?.map(\.plainText).joined() ?? "" }
        let totalWidth: CGFloat =
            plan.map { $0.widths.reduce(0, +) } ?? contentWidth
        let overflow = MarkdownTablePlan.overflows(
            totalWidth: Double(totalWidth), viewportWidth: Double(viewport))
        let planFits = plan.map {
            $0.widths.count == columns && $0.heights.count == rows.count + 1
        } ?? false
        // Pin only a label column on an overflowing table: short, non-numeric
        // first cells. Numbers scroll with their column; short tables need no pin.
        let pinned = MarkdownTablePlan.isLabelColumn(firstCells) && overflow && planFits
        Group {
            if pinned, let plan {
                pinnedTable(columns: columns, plan: plan)
            } else {
                scrollingTable(columns: columns, cacheKey: key)
            }
        }
        .accessibilityIdentifier("markdown.table")
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            viewport = $0
        }
        .paseoFeedback(.light, trigger: isExpanded) { _, new in new }
        .sheet(isPresented: $isExpanded) {
            SheetScaffold("Table", detents: .large) {
                ScrollView([.vertical, .horizontal]) {
                    ClaudeMarkdownTableLayout(
                        columns: columns, availableWidth: .greatestFiniteMagnitude,
                        maximumColumnWidth: max(50, theme.tableColumnWidth) + 24,
                        cacheKey: key + "|full", contentVersion: contentVersion
                    ) {
                        tableCells(columns: columns, headerTappable: false)
                    }
                    .padding(Space.md)
                }
            }
        }
    }

    /// The plan key: the table's path (same-header tables stay apart), its header text (stable
    /// while rows stream in) and the viewport bucket (rotation re-plans).
    private var planKey: String {
        MarkdownTablePlan.cacheKey(
            headerText: path + "|" + header.flatMap { $0.map(\.plainText) }.joined(separator: "|"),
            tableIndex: 0,
            viewportBucket: MarkdownTablePlan.viewportBucket(for: Double(max(viewport, 0))))
    }

    /// The scrolled table: the measuring layout, a content-width reader for the
    /// overflow signal, and a trailing fade (only when overflowing) that opens
    /// the full screen as well.
    @ViewBuilder
    private func scrollingTable(columns: Int, cacheKey: String) -> some View {
        let overflow = MarkdownTablePlan.overflows(
            totalWidth: Double(contentWidth), viewportWidth: Double(viewport))
        ScrollView(.horizontal) {
            ClaudeMarkdownTableLayout(
                columns: columns, availableWidth: viewport,
                maximumColumnWidth: max(50, theme.tableColumnWidth) + 24,
                cacheKey: cacheKey, contentVersion: contentVersion
            ) {
                tableCells(columns: columns, headerTappable: true)
            }
            .clipShape(.rect(cornerRadius: Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.sm).stroke(theme.rule, lineWidth: 0.6)
            }
            .background {
                // `onGeometryChange` instead of a `GeometryReader` per table (W1), written on change only.
                Color.clear.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newWidth in
                    if contentWidth != newWidth { contentWidth = newWidth }
                }
            }
        }
        .overlay(alignment: .trailing) {
            if overflow {
                Button {
                    isExpanded = true
                } label: {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Palette.background, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: Metrics.tableFadeWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open table full screen")
            }
        }
    }

    /// The pinned table: the label column fixed, the rest scrolling, row heights
    /// shared from the plan so the two stacks can never drift apart.
    @ViewBuilder
    private func pinnedTable(columns: Int, plan: TablePlanBox) -> some View {
        let allRows = [header] + rows
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(allRows.enumerated(), id: \.offset) { index, row in
                    let isHeader = index == 0
                    MarkdownTableCell(
                        cell: row.first ?? [], isHeader: isHeader,
                        alignment: alignments.first ?? .left, rowIndex: index,
                        rowsCount: rows.count, theme: theme, onExpand: expander(isHeader)
                    )
                    .frame(
                        width: plan.widths[0], height: plan.heights[index],
                        alignment: .topLeading)
                }
            }
            .frame(width: plan.widths[0], alignment: .top)
            ScrollView(.horizontal) {
                FixedTableLayout(
                    columns: columns - 1, widths: Array(plan.widths.dropFirst()),
                    heights: plan.heights
                ) {
                    ForEach(allRows.enumerated(), id: \.offset) { index, row in
                        let isHeader = index == 0
                        ForEach(1..<columns, id: \.self) { column in
                            let cell = column < row.count ? row[column] : []
                            let alignment =
                                column < alignments.count ? alignments[column] : .left
                            MarkdownTableCell(
                                cell: cell, isHeader: isHeader, alignment: alignment,
                                rowIndex: index, rowsCount: rows.count, theme: theme,
                                onExpand: expander(isHeader))
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: Radius.sm))
            }
            .clipShape(.rect(cornerRadius: Radius.sm))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm).stroke(theme.rule, lineWidth: 0.6)
        }
    }

    /// The shared cell ForEach for the measuring layouts, keyed by row content.
    @ViewBuilder
    private func tableCells(columns: Int, headerTappable: Bool) -> some View {
        ForEach(([header] + rows).identifiedRows()) { identified in
            let row = identified.value
            let isHeader = identified.index == 0
            ForEach(0..<columns, id: \.self) { column in
                let cell = column < row.count ? row[column] : []
                let alignment = column < alignments.count ? alignments[column] : .left
                MarkdownTableCell(
                    cell: cell, isHeader: isHeader, alignment: alignment,
                    rowIndex: identified.index, rowsCount: rows.count, theme: theme,
                    onExpand: expander(headerTappable && isHeader))
            }
        }
    }

    /// The full-screen action of a tappable header cell; nil for every other cell.
    private func expander(_ tappable: Bool) -> (() -> Void)? {
        guard tappable else { return nil }
        return { isExpanded = true }
    }
}
#endif
