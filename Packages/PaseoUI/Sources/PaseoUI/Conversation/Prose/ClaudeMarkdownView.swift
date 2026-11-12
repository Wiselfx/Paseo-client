#if canImport(UIKit)
    import PaseoStore
    import SwiftUI

    /// Theme values follow `docs/research/08-dsh-live-observation.md` §6: serif body, 12 pt between
    /// blocks, mono code. Sizes are measured at Claude's 17 pt body (V5); headings and code are
    /// ratios of `bodySize`, so the whole ladder follows the size setting and Dynamic Type.
    /// Claude's uncaptured rich-block metrics remain provisional.
    public struct ClaudeMarkdownTheme {
        public var bodyFont: Font
        public var headingFonts: [Font]
        public var codeFont: Font
        public var foreground: Color = Palette.ink
        public var secondary: Color = Palette.secondaryInk
        public var link: Color = Palette.proseLink
        public var inlineCodeForeground: Color = Palette.ink
        /// The blockquote's wash: rgba(20,20,19,0.04) light / rgba(250,249,245,0.06) dark.
        public var quoteWash: Color = Palette.quoteWash
        public var codeBackground: Color = Palette.codeSurface
        public var inlineCodeBackground: Color = Palette.inlineCodeFill
        public var tableHeaderBackground: Color = Palette.adaptive(light: 1, dark: 0.16)
        public var rule: Color = Palette.divider
        public var blockSpacing: CGFloat = 12
        public var lineSpacing: CGFloat = 9
        public var listSpacing: CGFloat = 9
        public var tableColumnWidth: CGFloat = 150
        public init(serifName: String = "Newsreader16pt-Regular", bodySize: CGFloat = 20) {
            foreground = Palette.ink
            // Dynamic Type (shifted by Content size in `RootView`) scales prose; the theme no
            // longer multiplies sizes by hand.
            bodyFont = ProseFonts.serif(size: bodySize)
            // The Claude ladder as ratios of the body: h1 1.5, h2 1.29, h3 1.14, h4 1, h5 0.93,
            // h6 0.86 (the sizes measured at 14 pt: 21 / 18 / 16 / 14 / 13 / 12).
            let headingRatios: [CGFloat] = [1.5, 1.286, 1.143, 1, 0.929, 0.857]
            headingFonts = headingRatios.enumerated().map { index, ratio in
                ProseFonts.serif(size: bodySize * ratio, relativeTo: index < 3 ? .headline : .body)
                    .weight(index < 3 ? .bold : .semibold)
            }
            // ~0.88 of the body: 15 pt at the 17 pt Claude body. The code-size step is applied by
            // the code container (`codeTypeScale()`), not baked into the face.
            codeFont = ProseFonts.mono(size: 15)
        }
        public static var artifact: Self {
            var theme = Self()
            theme.bodyFont = .system(size: 17)
            theme.codeFont = .system(size: 13, design: .monospaced)
            theme.lineSpacing = 6
            return theme
        }
    }

    public struct ClaudeMarkdownView: View {
        public let document: MarkdownDocumentModel
        public var theme: ClaudeMarkdownTheme
        @State private var tableViewport: CGFloat = 0
        @State private var expandedCode: ExpandedCode?
        /// Per-table content widths, by block index: the overflow signal. Written
        /// only when the width changes — never per scroll frame.
        @State private var tableContentWidths: [Int: CGFloat] = [:]
        @State private var expandedTable: ExpandedTable?
        private let codeContent: ((String?, String) -> AttributedString)?
        private let onAction: (MarkdownAction) -> Void
        /// True while the producing turn runs: code blocks wait for their fence to close before
        /// they ask the highlighter (R9 §1).
        private let isStreaming: Bool
        private let imageContent: ((MarkdownImage) -> AnyView)?
        private let unsupportedContent: ((MarkdownUnsupportedKind, String) -> AnyView)?
        public init(
            document: MarkdownDocumentModel, theme: ClaudeMarkdownTheme = .init(),
            imageContent: ((MarkdownImage) -> AnyView)? = nil,
            codeContent: ((String?, String) -> AttributedString)? = nil,
            unsupportedContent: ((MarkdownUnsupportedKind, String) -> AnyView)? = nil,
            isStreaming: Bool = false,
            onAction: @escaping (MarkdownAction) -> Void = { _ in }
        ) {
            self.document = document
            self.theme = theme
            self.imageContent = imageContent
            self.codeContent = codeContent
            self.unsupportedContent = unsupportedContent
            self.isStreaming = isStreaming
            self.onAction = onAction
        }
        public init(
            _ source: String, theme: ClaudeMarkdownTheme = .init(), isStreaming: Bool = false,
            onAction: @escaping (MarkdownAction) -> Void = { _ in }
        ) {
            self.init(
                document: .init(source: source), theme: theme, isStreaming: isStreaming,
                onAction: onAction)
        }
        public var body: some View {
            blocks(document.blocks).foregroundStyle(theme.foreground)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    tableViewport = $0
                }
                .sheet(item: $expandedCode) { item in
                    VStack(spacing: 30) {
                        ZStack {
                            Text(item.language.map { $0.prefix(1).uppercased() + $0.dropFirst() + " code" } ?? "Code")
                                .font(.system(size: 17, weight: .semibold))
                            HStack {
                                Button {
                                    expandedCode = nil
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 20)).frame(width: 44, height: 44)
                                }.glassEffect(in: .circle).accessibilityLabel("Close code").accessibilityIdentifier(
                                    "markdown.code.close")
                                Spacer()
                            }
                        }
                        ScrollView([.vertical, .horizontal]) {
                            codeText(language: item.language, content: item.content).accessibilityIdentifier(
                                "markdown.code.expandedContent")
                        }.defaultScrollAnchor(.topLeading, for: .alignment).frame(
                            maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }.padding(16).background(Palette.background).presentationDetents([.large])
                        .presentationDragIndicator(.hidden)
                }
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        if let local = MarkdownAction.decodePresentationURL(url) {
                            onAction(local)
                        } else {
                            onAction(.openLink(url))
                        }
                        return .handled
                    })
        }
        // Quotes and lists call back into `blocks`, so the opaque type would be defined in
        // terms of itself; one `AnyView` per container level breaks the cycle while every leaf
        // block keeps its concrete type.
        private func blocks(_ blocks: [MarkdownBlock]) -> AnyView {
            AnyView(
                VStack(alignment: .leading, spacing: theme.blockSpacing) {
                    ForEach(identifiedBlocks(blocks)) { identified in
                        render(identified.value, blockIndex: identified.index)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading))
        }

        /// One block plus a stable identity for `ForEach` (P5-B).
        ///
        /// Settled blocks are identified by their own content (hashed, plus their
        /// occurrence among identical blocks), so inserting or removing a block does not
        /// shift the identity of the blocks after it — the offset ids used before did.
        /// The open (last) block is identified by position instead: its text streams in,
        /// so a content hash would change on every token and SwiftUI would tear the block
        /// down and rebuild it, losing its internal state (e.g. a code block's scroll
        /// offset). Its position is stable while it grows.
        private func identifiedBlocks(_ blocks: [MarkdownBlock]) -> [IdentifiedValue<MarkdownBlock>] {
            identified(blocks) { block in
                var hasher = Hasher()
                block.hashStable(into: &hasher)
                return hasher.finalize()
            }
        }

        /// List items get the same treatment; the ordered-list number needs the index.
        private func identifiedItems(_ items: [MarkdownListItem]) -> [IdentifiedValue<MarkdownListItem>] {
            identified(items) { item in
                var hasher = Hasher()
                item.hashStable(into: &hasher)
                return hasher.finalize()
            }
        }

        /// Table rows, identified by their own cells.
        private func identifiedRows(_ rows: [[[MarkdownInline]]]) -> [IdentifiedValue<[[MarkdownInline]]>] {
            identified(rows) { row in
                var hasher = Hasher()
                for cell in row { cell.hashStable(into: &hasher) }
                return hasher.finalize()
            }
        }

        /// Wraps each value with a stable `ForEach` identity; see `identifiedBlocks`.
        private func identified<Value>(_ values: [Value], hashing: (Value) -> Int) -> [IdentifiedValue<Value>] {
            var occurrences: [Int: Int] = [:]
            let lastIndex = values.count - 1
            return values.enumerated().map { index, value in
                if index == lastIndex {
                    return IdentifiedValue(id: StableID(open: true, value: index, occurrence: 0), index: index, value: value)
                }
                let contentHash = hashing(value)
                let occurrence = occurrences[contentHash, default: 0]
                occurrences[contentHash] = occurrence + 1
                return IdentifiedValue(
                    id: StableID(open: false, value: contentHash, occurrence: occurrence), index: index, value: value)
            }
        }

        private struct StableID: Hashable {
            let open: Bool
            let value: Int
            let occurrence: Int
        }

        private struct IdentifiedValue<Value>: Identifiable {
            let id: StableID
            let index: Int
            let value: Value
        }

        /// Renders one block. `@ViewBuilder` (not `AnyView`, P5-B): type erasure hides the
        /// block type from SwiftUI's diff engine, so every prose re-render rebuilt the whole
        /// block subtree. The concrete type per branch lets unchanged blocks be skipped.
        @ViewBuilder private func render(_ block: MarkdownBlock, blockIndex: Int = 0) -> some View {
            switch block {
            case .paragraph(let content):
                if content.count == 1, case .image(let image) = content[0], let imageContent {
                    imageContent(image)
                } else {
                    inline(content)
                }
            case .heading(let level, let content):
                inline(
                    content,
                    font: (theme.headingFonts.isEmpty
                        ? theme.bodyFont.bold()
                        : theme.headingFonts[min(max(level - 1, 0), theme.headingFonts.count - 1)])
                ).accessibilityAddTraits(.isHeader)
            case .rule:
                Rectangle().fill(theme.rule).frame(height: 1).accessibilityLabel("Horizontal rule")
            case .quote(let children):
                blocks(children)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 14) // .6em 1em ≈ .6em vertical, 1em horizontal
                    .padding(.vertical, 8.4)
                    .background(
                        theme.quoteWash,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 8,
                            topTrailingRadius: 8))
                    .accessibilityIdentifier("markdown.quote")
            case .list(let start, let items):
                VStack(alignment: .leading, spacing: theme.listSpacing) {
                    ForEach(identifiedItems(items)) { identified in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(
                                identified.value.checked.map { $0 ? "☑" : "☐" }
                                    ?? start.map { "\($0 + identified.index)." } ?? "•"
                            ).font(theme.bodyFont).frame(minWidth: 18, alignment: .trailing)
                            blocks(identified.value.blocks)
                        }
                    }
                }.accessibilityIdentifier("markdown.list")
            case .code(let language, let content):
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(language ?? "").font(.system(size: 14, design: .monospaced)).foregroundStyle(
                            theme.secondary)
                        Spacer()
                        Button {
                            onAction(.copyCode(content))
                        } label: {
                            Image(systemName: "square.on.square")
                                .frame(width: 28, height: 28)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }.accessibilityLabel("Copy code").accessibilityIdentifier("markdown.code.copy")
                        Button {
                            expandedCode = .init(language: language, content: content)
                            onAction(.expandCode(language: language, content: content))
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 28, height: 28)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }.accessibilityLabel("Expand code").accessibilityIdentifier("markdown.code.expand")
                        // Preview is explicit and never automatic (G5 §2 C8): closed html/svg
                        // fences offer it; a streaming fence is still arriving, so it doesn't.
                        if !isStreaming, let language,
                            ["html", "svg"].contains(
                                language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        {
                            Button {
                                onAction(.previewCode(language: language, content: content))
                            } label: {
                                Image(systemName: "eye")
                                    .frame(width: Metrics.codeIconSize, height: Metrics.codeIconSize)
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }.accessibilityLabel("Preview").accessibilityIdentifier(
                                "markdown.code.preview")
                        }
                    }.foregroundStyle(theme.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                    Rectangle().fill(theme.rule).frame(height: 0.5)
                    ScrollView(.horizontal) {
                        codeText(language: language, content: content).accessibilityIdentifier(
                            "markdown.code.content")
                    }.scrollIndicators(.hidden).padding(16)
                }.background(theme.codeBackground, in: .rect(cornerRadius: Radius.group)).overlay {
                    RoundedRectangle(cornerRadius: Radius.group).stroke(theme.rule, lineWidth: 0.6)
                }
            case .table(let header, let rows, let alignments):
                tableBlock(
                    header: header, rows: rows, alignments: alignments,
                    blockIndex: blockIndex)
            case .unsupported(let kind, let source):
                if let unsupportedContent {
                    unsupportedContent(kind, source)
                } else {
                    Text(verbatim: source).font(theme.codeFont).textSelection(.enabled).contextMenu {
                        Button("Open content") { onAction(.unsupported(kind: kind, source: source)) }
                    }
                }
            }
        }
        // MARK: Wide tables (Phase C §9.1)

        /// One table opened full screen: the block plus an identity for the sheet.
        private struct ExpandedTable: Identifiable {
            let index: Int
            let header: [[MarkdownInline]]
            let rows: [[[MarkdownInline]]]
            let alignments: [MarkdownColumnAlignment]
            let columns: Int
            var id: Int { index }
        }

        /// The plan key: header text (stable while rows stream in), the block index
        /// (same-header tables stay apart) and the viewport bucket (rotation re-plans).
        private func tablePlanKey(header: [[MarkdownInline]], blockIndex: Int) -> String {
            MarkdownTablePlan.cacheKey(
                headerText: header.flatMap { $0.map(\.plainText) }.joined(separator: "|"),
                tableIndex: blockIndex,
                viewportBucket: MarkdownTablePlan.viewportBucket(for: Double(max(tableViewport, 0))))
        }

        /// Horizontal scroll inside the block, pinned label column when the table
        /// earns it, header tap to full screen. Rows append downward with stable
        /// ids; widths come from the plan cache and only ever grow.
        @ViewBuilder
        private func tableBlock(
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], blockIndex: Int
        ) -> some View {
            let columns = max(header.count, rows.map(\.count).max() ?? 0)
            let key = tablePlanKey(header: header, blockIndex: blockIndex)
            let plan = MarkdownTablePlanCache.lookup(key: key)
            let firstCells = rows.map { $0.first?.map(\.plainText).joined() ?? "" }
            let contentWidth = tableContentWidths[blockIndex] ?? 0
            let totalWidth: CGFloat =
                plan.map { $0.widths.reduce(0, +) } ?? contentWidth
            let overflow = MarkdownTablePlan.overflows(
                totalWidth: Double(totalWidth), viewportWidth: Double(tableViewport))
            let planFits = plan.map {
                $0.widths.count == columns && $0.heights.count == rows.count + 1
            } ?? false
            // Pin only a label column on an overflowing table: short, non-numeric
            // first cells. Numbers scroll with their column; short tables need no pin.
            let pinned = MarkdownTablePlan.isLabelColumn(firstCells) && overflow && planFits
            let contentVersion = document.tableVersions[blockIndex] ?? 0
            Group {
                if pinned, let plan {
                    pinnedTable(
                        header: header, rows: rows, alignments: alignments,
                        columns: columns, plan: plan, blockIndex: blockIndex)
                } else {
                    scrollingTable(
                        header: header, rows: rows, alignments: alignments,
                        columns: columns, cacheKey: key, contentVersion: contentVersion,
                        blockIndex: blockIndex)
                }
            }
            .accessibilityIdentifier("markdown.table")
            .sheet(item: $expandedTable) { table in
                SheetScaffold("Table", detents: .large) {
                    ScrollView([.vertical, .horizontal]) {
                        ClaudeMarkdownTableLayout(
                            columns: table.columns, availableWidth: .greatestFiniteMagnitude,
                            maximumColumnWidth: max(50, theme.tableColumnWidth) + 24,
                            cacheKey: key + "|full",
                            contentVersion: document.tableVersions[table.index] ?? 0
                        ) {
                            tableCells(
                                header: table.header, rows: table.rows,
                                alignments: table.alignments, columns: table.columns,
                                rowsCount: table.rows.count, headerTappable: false)
                        }
                        .padding(Space.md)
                    }
                }
            }
        }

        /// The scrolled table: the measuring layout, a content-width reader for the
        /// overflow signal, and a trailing fade (only when overflowing) that opens
        /// the full screen as well.
        @ViewBuilder
        private func scrollingTable(
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], columns: Int, cacheKey: String,
            contentVersion: Int, blockIndex: Int
        ) -> some View {
            let overflow = MarkdownTablePlan.overflows(
                totalWidth: Double(tableContentWidths[blockIndex] ?? 0),
                viewportWidth: Double(tableViewport))
            ScrollView(.horizontal) {
                ClaudeMarkdownTableLayout(
                    columns: columns, availableWidth: tableViewport,
                    maximumColumnWidth: max(50, theme.tableColumnWidth) + 24,
                    cacheKey: cacheKey, contentVersion: contentVersion
                ) {
                    tableCells(
                        header: header, rows: rows, alignments: alignments,
                        columns: columns, rowsCount: rows.count, headerTappable: true,
                        blockIndex: blockIndex)
                }
                .clipShape(.rect(cornerRadius: Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sm).stroke(theme.rule, lineWidth: 0.6)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { tableContentWidths[blockIndex] = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newWidth in
                                tableContentWidths[blockIndex] = newWidth
                            }
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if overflow {
                    Button {
                        expandTable(
                            header: header, rows: rows, alignments: alignments,
                            columns: columns, blockIndex: blockIndex)
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
        private func pinnedTable(
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], columns: Int, plan: TablePlanBox,
            blockIndex: Int
        ) -> some View {
            let allRows = [header] + rows
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(allRows.enumerated()), id: \.offset) { index, row in
                        let isHeader = index == 0
                        tableCell(
                            row.first ?? [], isHeader: isHeader,
                            alignment: alignments.first ?? .left, rowIndex: index,
                            rowsCount: rows.count, headerTappable: isHeader,
                            blockIndex: blockIndex, header: header, rows: rows,
                            alignments: alignments, columns: columns)
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
                        ForEach(Array(allRows.enumerated()), id: \.offset) { index, row in
                            let isHeader = index == 0
                            ForEach(1..<columns, id: \.self) { column in
                                let cell = column < row.count ? row[column] : []
                                let alignment =
                                    column < alignments.count ? alignments[column] : .left
                                tableCell(
                                    cell, isHeader: isHeader, alignment: alignment,
                                    rowIndex: index, rowsCount: rows.count,
                                    headerTappable: isHeader, blockIndex: blockIndex,
                                    header: header, rows: rows, alignments: alignments,
                                    columns: columns)
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

        /// One cell: the inline content, the header wash, the row divider, and the
        /// header's full-screen tap target.
        @ViewBuilder
        private func tableCell(
            _ cell: [MarkdownInline], isHeader: Bool, alignment: MarkdownColumnAlignment,
            rowIndex: Int, rowsCount: Int, headerTappable: Bool, blockIndex: Int,
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], columns: Int
        ) -> some View {
            inline(
                cell, font: isHeader ? theme.bodyFont.bold() : theme.bodyFont,
                alignment: alignment
            )
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(isHeader ? theme.tableHeaderBackground : .clear)
            .overlay(alignment: .bottom) {
                if rowIndex < rowsCount { Rectangle().fill(theme.rule).frame(height: 0.5) }
            }
            .contentShape(.rect)
            .accessibilityHint(isHeader ? "Opens table full screen" : "")
            .onTapGesture {
                guard isHeader, headerTappable else { return }
                expandTable(
                    header: header, rows: rows, alignments: alignments, columns: columns,
                    blockIndex: blockIndex)
            }
        }

        /// The shared cell ForEach for the measuring layouts, keyed by row content.
        @ViewBuilder
        private func tableCells(
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], columns: Int, rowsCount: Int,
            headerTappable: Bool, blockIndex: Int = 0
        ) -> some View {
            ForEach(identifiedRows([header] + rows)) { identified in
                let row = identified.value
                let isHeader = identified.index == 0
                ForEach(0..<columns, id: \.self) { column in
                    let cell = column < row.count ? row[column] : []
                    let alignment = column < alignments.count ? alignments[column] : .left
                    tableCell(
                        cell, isHeader: isHeader, alignment: alignment,
                        rowIndex: identified.index, rowsCount: rowsCount,
                        headerTappable: headerTappable && isHeader, blockIndex: blockIndex,
                        header: header, rows: rows, alignments: alignments,
                        columns: columns)
                }
            }
        }

        private func expandTable(
            header: [[MarkdownInline]], rows: [[[MarkdownInline]]],
            alignments: [MarkdownColumnAlignment], columns: Int, blockIndex: Int
        ) {
            Haptics.light()
            expandedTable = ExpandedTable(
                index: blockIndex, header: header, rows: rows, alignments: alignments,
                columns: columns)
        }

        @ViewBuilder private func inline(
            _ content: [MarkdownInline], font: Font? = nil, alignment: MarkdownColumnAlignment = .left
        ) -> some View {
            if content.contains(where: \.containsInlineCode) {
                ClaudeSelectableInlineCode(
                    content: content, font: font ?? theme.bodyFont, theme: theme,
                    alignment: alignment == .right ? .right : alignment == .center ? .center : .left, onAction: onAction
                )
            } else {
                inlineText(content, font: font ?? theme.bodyFont)
                    .textRenderer(InlineCodeRenderer(background: Palette.inlineCodeFill))
                    .lineSpacing(theme.lineSpacing).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        maxWidth: .infinity,
                        alignment: alignment == .right ? .trailing : alignment == .center ? .center : .leading)
            }
        }
        /// First paint is plain mono in ink; the highlighted tokens swap in from the actor with the
        /// same font and metrics, so there is no layout jump (R9 §1).
        @ViewBuilder private func codeText(language: String?, content: String) -> some View {
            if let codeContent {
                Text(codeContent(language, content))
                    .font(theme.codeFont)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .codeTypeScale()
            } else {
                ClaudeHighlightedCode(
                    language: language, content: content, theme: theme,
                    isStreaming: isStreaming
                )
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
                .codeTypeScale()
            }
        }
        private func inlineText(
            _ children: [MarkdownInline], font: Font, bold: Bool = false, italic: Bool = false, strike: Bool = false,
            link: URL? = nil
        ) -> Text {
            children.reduce(Text("")) { result, child in
                let piece: Text
                switch child {
                case .strong(let nested):
                    piece = inlineText(nested, font: font, bold: true, italic: italic, strike: strike, link: link)
                case .emphasis(let nested):
                    piece = inlineText(nested, font: font, bold: bold, italic: true, strike: strike, link: link)
                case .strikethrough(let nested):
                    piece = inlineText(nested, font: font, bold: bold, italic: italic, strike: true, link: link)
                case .link(let destination, let nested):
                    piece = inlineText(
                        nested, font: font, bold: bold, italic: italic, strike: strike, link: URL(string: destination))
                default:
                    var value = attributed([child], font: font, bold: bold, italic: italic, strike: strike)
                    if let link {
                        value.link = link
                        value.foregroundColor = theme.link
                        value.underlineStyle = .single
                        value.font = value.font?.weight(.medium) // the prose link is 500
                    }
                    if case .code = child {
                        piece = Text(value).customAttribute(InlineCodeAttribute())
                    } else {
                        piece = Text(value)
                    }
                }
                return Text("\(result)\(piece)")
            }
        }
        private func attributed(
            _ children: [MarkdownInline], font: Font, bold: Bool = false, italic: Bool = false, strike: Bool = false
        ) -> AttributedString {
            var result = AttributedString()
            for child in children {
                var run = AttributedString()
                switch child {
                case .strong(let children):
                    run = attributed(children, font: font, bold: true, italic: italic, strike: strike)
                case .emphasis(let children):
                    run = attributed(children, font: font, bold: bold, italic: true, strike: strike)
                case .strikethrough(let children):
                    run = attributed(children, font: font, bold: bold, italic: italic, strike: true)
                case .link(let destination, let children):
                    run = attributed(children, font: font, bold: bold, italic: italic, strike: strike)
                    run.link = URL(string: destination)
                    run.foregroundColor = theme.link
                    run.underlineStyle = .single
                default:
                    let value: String
                    switch child {
                    case .image(let image): value = "▧ " + (image.alt.isEmpty ? "Image" : image.alt)
                    default: value = child.plainText
                    }
                    run = AttributedString(value)
                    var face = font
                    if case .code = child {
                        face = theme.codeFont
                        run.foregroundColor = theme.inlineCodeForeground
                    }
                    if bold { face = face.weight(.semibold) } // DSH strong is 600, not 700
                    if italic { face = face.italic() }
                    run.font = face
                    run.strikethroughStyle = strike ? .single : nil
                    if case .image(let image) = child {
                        run.link = MarkdownAction.image(image).presentationURL
                        run.foregroundColor = theme.link
                    }
                    if case .unsupported(let kind, let source) = child {
                        run.link = MarkdownAction.unsupported(kind: kind, source: source).presentationURL
                    }
                }
                result.append(run)
            }
            return result
        }
    }
    private struct ExpandedCode: Identifiable {
        let id = UUID()
        let language: String?
        let content: String
    }
    private struct InlineCodeAttribute: TextAttribute {}
    private struct InlineCodeRenderer: TextRenderer {
        var background: Color
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line {
                    if run[InlineCodeAttribute.self] != nil {
                        context.fill(
                            Path(roundedRect: run.typographicBounds.rect.insetBy(dx: -1, dy: -1), cornerRadius: Radius.xs),
                            with: .color(background))
                    }
                    context.draw(run)
                }
            }
        }
    }

/// Content hashes for the stable `ForEach` identities (P5-B). `MarkdownBlock` is only
/// `Equatable` (its public contract), so the hash is written out rather than synthesized.
private extension MarkdownInline {
    func hashStable(into hasher: inout Hasher) {
        switch self {
        case .text(let value): hasher.combine("text"); hasher.combine(value)
        case .softBreak: hasher.combine("softBreak")
        case .hardBreak: hasher.combine("hardBreak")
        case .code(let value): hasher.combine("code"); hasher.combine(value)
        case .emphasis(let children): hasher.combine("emphasis"); children.hashStable(into: &hasher)
        case .strong(let children): hasher.combine("strong"); children.hashStable(into: &hasher)
        case .strikethrough(let children): hasher.combine("strikethrough"); children.hashStable(into: &hasher)
        case .link(let destination, let children):
            hasher.combine("link"); hasher.combine(destination); children.hashStable(into: &hasher)
        case .image(let image):
            hasher.combine("image")
            hasher.combine(image.source)
            hasher.combine(image.title ?? "")
            hasher.combine(image.alt)
        case .unsupported(let kind, let source):
            hasher.combine("unsupported"); hasher.combine(kind.rawValue); hasher.combine(source)
        }
    }
}

private extension Array where Element == MarkdownInline {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for child in self { child.hashStable(into: &hasher) }
    }
}

private extension MarkdownListItem {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(checked ?? false)
        hasher.combine(checked == nil)
        blocks.hashStable(into: &hasher)
    }
}

private extension MarkdownBlock {
    func hashStable(into hasher: inout Hasher) {
        switch self {
        case .paragraph(let content): hasher.combine("paragraph"); content.hashStable(into: &hasher)
        case .heading(let level, let content):
            hasher.combine("heading"); hasher.combine(level); content.hashStable(into: &hasher)
        case .quote(let children): hasher.combine("quote"); children.hashStable(into: &hasher)
        case .rule: hasher.combine("rule")
        case .list(let start, let items):
            hasher.combine("list"); hasher.combine(start ?? -1); hasher.combine(items.count)
            for item in items { item.hashStable(into: &hasher) }
        case .code(let language, let content):
            hasher.combine("code"); hasher.combine(language ?? ""); hasher.combine(content)
        case .table(let header, let rows, let alignments):
            hasher.combine("table")
            header.hashStable(into: &hasher)
            hasher.combine(rows.count)
            for row in rows { row.hashStable(into: &hasher) }
            hasher.combine(alignments.count)
            for alignment in alignments {
                switch alignment {
                case .left: hasher.combine(0)
                case .center: hasher.combine(1)
                case .right: hasher.combine(2)
                }
            }
        case .unsupported(let kind, let source):
            hasher.combine("unsupported"); hasher.combine(kind.rawValue); hasher.combine(source)
        }
    }
}

private extension Array where Element == MarkdownBlock {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for block in self { block.hashStable(into: &hasher) }
    }
}

private extension Array where Element == [MarkdownInline] {
    func hashStable(into hasher: inout Hasher) {
        hasher.combine(count)
        for row in self { row.hashStable(into: &hasher) }
    }
}

/// One fenced code block, highlighted **after** first paint (R9 §1).
///
/// The plain mono text is what mounts; the actor's tokens arrive a moment later and replace it with
/// the same font and metrics, so nothing moves. While the producing turn is still streaming the
/// block waits — the last fence of a running answer is not closed yet — and highlights once the
/// turn ends.
struct ClaudeHighlightedCode: View {
    let language: String?
    let content: String
    let theme: ClaudeMarkdownTheme
    /// The reveal's "still arriving" signal: true while the producing turn runs.
    let isStreaming: Bool

    @State private var highlighted: AttributedString?
    @Environment(\.colorScheme) private var colorScheme

    private var syntaxTheme: ClaudeCodeSyntaxTheme {
        colorScheme == .dark ? .dark : .light
    }

    /// Identity of the request: language, theme and the text's length. The actor caches on the
    /// source hash, so two revisions of different length are two entries, and a re-render of the
    /// same block asks for the same one.
    private var requestKey: String {
        "\(syntaxTheme.rawValue)/\(language ?? "")/\(content.utf16.count)"
    }

    var body: some View {
        Text(highlighted ?? AttributedString(content))
            .font(theme.codeFont)
            .foregroundStyle(theme.foreground)
            .task(id: requestKey) {
                guard !isStreaming else { return }
                let result = await CodeHighlighter.shared.highlight(
                    content, language: language, theme: syntaxTheme)
                if highlighted != result { highlighted = result }
            }
            .onChange(of: isStreaming) { _, streaming in
                guard !streaming else { return }
                Task {
                    let result = await CodeHighlighter.shared.highlight(
                        content, language: language, theme: syntaxTheme)
                    if highlighted != result { highlighted = result }
                }
            }
    }
}
#endif
