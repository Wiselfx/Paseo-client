# R2: design tokens: one type scale, one palette, one motion set

Branch: `r2-tokens`, from `foundation` **after R1 is merged**, so paths are the new folders. Read
`docs/tickets/_R-common.md` first.

This ticket owns every file under `Packages/PaseoUI/Sources/PaseoUI/` (token replacements) and
`App/Sources/RootView.swift`. It runs alone. Plan: `docs/refactor/PLAN.md` §RA1, §RA5.

You make **no taste decisions**. Every mapping you need is in the tables below. Where a site doesn't
fit a rule, use the nearest rule and list the site under "Unsure".

## 1. Typography: roles, cached fonts, native Dynamic Type

### 1.1 New file `DesignSystem/Typography.swift`

```swift
/// Text roles. Each maps to one face, size and Dynamic Type style, resolved once.
enum TextRole {
    case largeTitle   // serif 28, relativeTo .largeTitle — sidebar "Paseo", hero lines
    case title        // serif 20, relativeTo .title3     — chat header title, sheet hero titles
    case headline     // sans 17 semibold, .headline     — section and row titles that lead
    case body         // sans 17, .body                  — chat body, composer, settings rows
    case callout      // sans 15, .callout               — secondary rows, buttons, chips
    case footnote     // sans 13, .footnote              — metadata, captions under rows
    case caption      // sans 12, .caption               — small metadata
    case caption2     // sans 11, .caption2              — badges, pills, counters
    case code         // mono 13, .footnote              — code blocks, tool output, diffs
    case codeSmall    // mono 12, .caption               — dense code (gutters, chips)
    case codeCaption  // mono 11, .caption2              — line numbers, tiny mono labels
}

extension Font {
    /// The one way to get a text font. Weight is applied on top, never baked into the role
    /// (except `headline`).
    static func paseo(_ role: TextRole, weight: Font.Weight? = nil) -> Font
}

/// SF Symbol sizes. Icons are not text roles.
enum GlyphSize { case small /*13*/, regular /*17*/, large /*20*/, xlarge /*28*/, hero /*34*/ }

extension Font {
    static func glyph(_ size: GlyphSize, weight: Font.Weight = .regular) -> Font
    // .system(size:weight:) scaled with relativeTo
}
```

**Implementation rules:**
- `Font.custom(name, size:, relativeTo:)`, with the face names resolved **once**:
  - a `static let` computed after `ClaudeFontResources.register()`;
  - `Typography` calls `register()` in its static initializer;
  - the fallback chain is serif → Newsreader → `.system(design: .serif)`;
  - the fallback keeps the **size**: `.system(size:weight:design:)` scaled through `relativeTo`
    via `UIFontMetrics`, never `.system(style)`, which loses the size.
- Cache every `(role, weight)` `Font` in a static dictionary, so `body` never calls CoreText.
- `ClaudeTypography` stays as a thin deprecated facade, **only** for the prose/markdown code
  (`Conversation/Prose/`), which keeps its own sizes (§1.4). Every other caller moves to
  `Font.paseo(...)`.

### 1.2 Content and code size become native Dynamic Type

Delete the per-call multipliers (`ClaudeTextScale.contentMultiplier()` / `codeMultiplier()` reads
inside font creation). Instead:

- **Content size:** in `RootView`, read the system `@Environment(\.dynamicTypeSize)` and the
  `@AppStorage(ClaudeTextScale.contentStorageKey)` step (S = −1, M = 0, L = +1, XL = +2). Apply
  `.dynamicTypeSize(shifted)` to the whole shell. `shifted` moves along `DynamicTypeSize.allCases`
  by the step, clamped to the ends.
- **Code size:** an environment value `\.codeSizeStep: Int` (same S/M/L/XL mapping), set in
  `RootView`. Code views (`code` / `codeSmall` / `codeCaption` users, and `Prose/` code blocks) apply
  `.dynamicTypeSize(current shifted by codeSizeStep)` on the code container.
- **Terminal:** `PaseoTerminalView` keeps its explicit multiplier (SwiftTerm needs a `UIFont` size).
  Leave it as is.
- **Delete `.id(rebuildKey)` and `rebuildKey` in `RootView`.** A size change must apply live
  without resetting the shell.

### 1.3 Mechanical replacement (every file outside `Conversation/Prose/`)

**Text fonts** (`.font(...)` on a `Text`, a `Label`, a `Button` label that is text, a `TextField`, or a
container of text), from `.system(size: N…)` or `typography.sans/serif/mono(N…)`:

| Source size and face | Role |
|---|---|
| sans/system ≤ 11 (incl. 9, 10, 10.5, 11) | `.caption2` |
| sans/system 12 | `.caption` |
| sans/system 12.5, 13 | `.footnote` |
| sans/system 14, 15, 16 | `.callout` |
| sans/system 17, 18 | `.body` |
| sans/system 17–18 **semibold** used as a title | `.headline` |
| serif 17–22 | `.title` |
| serif 24–34 | `.largeTitle` |
| serif 56 (the home hero greeting) | keep a dedicated `TextRole.hero` (serif 34, `.largeTitle`) and list it |
| mono ≤ 11.5 | `.codeCaption` |
| mono 12, 12.5 | `.codeSmall` |
| mono ≥ 13 | `.code` |

- Keep the original weight (`weight:` argument).
- `headline` already carries semibold, so don't double it.
- Where the source used `relativeTo:`, the role replaces it.

**Icon fonts** (`.font` on an `Image(systemName:)`, or on a `Button` whose label is only an `Image`):

| Source size | Glyph |
|---|---|
| ≤ 14 | `.glyph(.small)` |
| 15–18 | `.glyph(.regular)` |
| 19–24 | `.glyph(.large)` |
| 25–30 | `.glyph(.xlarge)` |
| ≥ 31 | `.glyph(.hero)` |

Keep the original weight.

**Layout guard:** when you change a font in a view that has a fixed `.frame(height: H)` containing
text, change it to `.frame(minHeight: H)`, so Dynamic Type grows instead of clipping. Leave fixed
heights on pure icons and on shapes alone.

`let typography = ClaudeTypography()` properties and `typography:` parameters disappear from
every view that no longer needs them. Prose callers keep passing it.

### 1.4 Prose (`Conversation/Prose/`)

- Prose keeps its exact sizes: the markdown theme, the reveal and the rich blocks.
- Route its fonts through one cached builder:
  `ProseFonts.serif(size:)`, `ProseFonts.sans(size:)`, `ProseFonts.mono(size:)`, each with
  `relativeTo: .body` so the shifted Dynamic Type scales prose too.
- Delete `ClaudeTextScale.contentMultiplier()` from `ClaudeMarkdownView.swift:30`; Dynamic Type now
  does the scaling.
- **Inline code plate:**
  - `InlineCodeRenderer` is defined but never applied. Today inline code gets a flat rectangular
    `backgroundColor` run attribute in `attributed(...)`, and the `customAttribute` path inside
    links draws nothing.
  - Make inline code one style everywhere: remove the flat `backgroundColor` and tag every code
    run with `InlineCodeAttribute`. Do this with `Text` concatenation, as the link path already
    does: build code runs as `Text(value).customAttribute(InlineCodeAttribute())`.
  - Apply `.textRenderer(InlineCodeRenderer(background: Palette.inlineCodeFill))` on the prose
    paragraph `Text`.
  - The result is a 4 pt rounded plate behind inline code.
  - If concatenating `Text` breaks link tapping or selection in a way you can't resolve, keep the
    current flat background and say so.

## 2. Palette (`DesignSystem/ClaudeStyle.swift` → `DesignSystem/Palette.swift`)

- **Rename** `enum ClaudePalette` → `enum Palette`, and add `typealias ClaudePalette = Palette` for this
  round only.
- **Merges**, each mapped at every call site:

  | From | To |
  |---|---|
  | `primaryInk`, `shimmerInk` | `ink`, but keep **`ink`'s** values only if they equal `primaryInk`'s; they differ (`ink` is warm #F2EFE9 dark / #212121 light; `primaryInk` is #FDFDFD / #161616). Use **`primaryInk`'s values** for the merged `ink` (it is the DSH label ink the turn layout uses; the chrome was the outlier). |
  | `secondary` (non-adaptive gray 0.56) | `secondaryInk` on text, `tertiaryInk` on icons and chevrons |
  | `codeBackground` | `codeSurface` |

- **New tokens:**

  | Token | Value |
  |---|---|
  | `diffAdded` | `successInk.opacity(0.14)` |
  | `diffRemoved` | `failureInk.opacity(0.14)` |
  | `diffAddedInk` | `successInk` |
  | `diffRemovedInk` | `failureInk` |
  | `selection` | `Color.blue` (checkmarks, selected tiles, toggles per UX-SPEC §0.1) |
  | `toggleTint` | `Color.blue` |

  These replace the private tints in `WorkspaceChangesDiffView`, the `successInk.opacity` uses in
  `ClaudeToolDetail`, and every `.tint(.blue)` / `Color.blue` / `.foregroundStyle(.blue)`. Map each
  to `selection` or `toggleTint` by what it styles.
- **Terminal:** the hand-copied ink/background in `PaseoTerminalView.swift:54-55` and
  `PaseoTerminalKeyBar.swift:34,47` become `UIColor(Palette.ink)` etc. Delete `ClaudePaletteWarm`;
  `controlActive` becomes `Palette.orange`.
- **The appearance swatch colors,** copy-pasted in Settings and `WelcomeView`, become
  `Palette.Swatch.light/dark/pureBlack` (same values) in `DesignSystem/`.
- **`.gray`, `.secondary`, `Color.primary` in UI code:** map to `secondaryInk` / `tertiaryInk` / `ink`.
- **Pure black, live:**
  - Replace the `UserDefaults` read inside every `UIColor` provider with a custom UIKit trait:
    - `struct PureBlackTrait: UITraitDefinition` (default false);
    - an `EnvironmentKey` `\.pureBlack`, bridged through `UITraitBridgedEnvironmentKey`;
    - providers read `traits[PureBlackTrait.self]`;
    - `RootView` sets `.environment(\.pureBlack, appearance == .pureBlack)`.
  - Switching Dark ↔ Pure black then redraws live.
  - These are iOS 17 APIs: list them under "Unsure" if you are not sure of the exact protocol
    requirements (`read(from:)` / `write(to:value:)`). If it can't work, keep a **narrow** rebuild
    key with only the pure-black flag, and say so.
- **Storage keys:** delete the duplicate `PaseoSettingsKeys.appearance` (`ClaudeAppearance.storageKey`
  is the one). Move `PaseoSettingsKeys` to `DesignSystem/SettingsKeys.swift`.

## 3. Radius (`DesignSystem/Metrics.swift`)

```swift
enum Radius {
    static let xs: CGFloat = 4    // inline code, tiny marks
    static let sm: CGFloat = 8    // chips' inner marks, small tiles
    static let md: CGFloat = 12   // cards, code blocks, tool cards, banners
    static let lg: CGFloat = 16   // large cards, permission card
    static let bubble: CGFloat = 20 // the user bubble (keep 20)
    static let group: CGFloat = 28  // grouped row blocks (`RowGroup`), composer card
}
enum Space { static let xs: CGFloat = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 24, xxxl = 32 }
```

Every literal corner radius maps to the nearest token:

| Literal radius | Token |
|---|---|
| 4–5 | `xs` |
| 6–9 | `sm` |
| 10–14 | `md` |
| 15–18 | `lg` |
| 19–22 | `bubble` (only on bubbles; elsewhere `lg`) |
| 24–30 | `group` |

Capsules and circles stay. The composer card's expanded radius (whatever `ComposerCardChrome` uses)
becomes `group`.

**Delete every `.presentationCornerRadius(...)`**, so sheets use the iOS 26 system shape.

Spacing literals are **not** replaced in this ticket. `Space` exists for the screen tickets.

## 4. Motion (`DesignSystem/Motion.swift`)

```swift
enum Motion {
    case feedback   // .easeOut(duration: 0.12)  press states, symbol swaps
    case fade       // .easeOut(duration: 0.2)   opacity / insert-remove transitions
    case disclosure // .smooth(duration: 0.25)   expand/collapse, size and layout changes
    case settle     // .smooth(duration: 0.32)   surfaces (= EdgeDrawer.settleAnimation)
    case glide      // .smooth(duration: 0.3)    programmatic scrolls
    case bubbleEnter // .timingCurve(0.22, 1, 0.36, 1, duration: 0.2) — the user bubble's entrance
    var animation: Animation { … }
    /// nil under Reduce Motion except for `fade`, which stays (opacity is allowed), and `settle`,
    /// which becomes .easeOut(duration: 0.2).
    func resolved(reduceMotion: Bool) -> Animation?
}
```

Replace every literal animation (`.easeOut(duration:)`, `.easeInOut(…)`, `.spring(…)`,
`.smooth(…)`, `.snappy`, `.bouncy`, `.linear(duration:)` used as UI motion):

- duration < 0.16 → `.feedback`;
- otherwise, if it animates only opacity or an insertion/removal transition → `.fade`;
- otherwise, if it is a programmatic `scrollTo` → `.glide`;
- otherwise, duration ≤ 0.28 → `.disclosure`;
- otherwise → `.settle`;
- any spring with bounce (`dampingFraction < 1`, `.bouncy`, `.snappy` with extraBounce) → `.disclosure`
  (UX-SPEC §0.4: no bounce).

The pattern `reduceMotion ? nil : X` becomes `Motion.x.resolved(reduceMotion: reduceMotion)`.
Keep `ClaudeMotion` (the DSH timing constants) as it is; it is not UI curves. `EdgeDrawer.settleAnimation`
returns `Motion.settle.resolved(...)`. **Leave `linear` animations that drive a continuous loop
(spinners, sweeps, `TimelineView`) alone.**

## 5. Haptics

- `Haptics.isEnabled` becomes a cached static, refreshed by
  `NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification…)` (or a setter
  called from Settings). Behavior is unchanged.
- Route the three bypasses through `Haptics`:
  - `ComposerQueue.swift` `QueueHaptics` (medium impact) → add `Haptics.medium()`;
  - `PaseoTerminalKeyBar.swift` → `Haptics.light()`;
  - `ConnectView.swift` `.sensoryFeedback(.error)` → `Haptics.failure()` at the same moment.

## 6. Style lint (`Tools/style-lint/style-lint.sh`)

A bash script: `style-lint.sh [path]` prints `file:line: rule` for every violation outside
`DesignSystem/`, then a per-file count and a total. Rules (grep -E):

- `\.system\(size:`
- `Color\(red:`
- `Color\(white:`
- `UIColor\(red:`
- `UIColor\(white:`
- `cornerRadius: [0-9]`
- `\.easeOut\(duration:` / `\.easeInOut\(` / `\.spring\(` / `\.smooth\(duration:` / `\.snappy` / `\.bouncy`
- `\.tint\(\.blue\)` / `Color\.blue` / `\.foregroundStyle\(\.blue\)`
- `ClaudeTypography\(\)`
- `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` / `sensoryFeedback`
- `ClaudePalette\.secondary\b`

Exit code 0 always; it is a report. **After this ticket, the total must be 0 outside
`Conversation/Prose/`.** Report the before and after totals. Allowed leftovers (list each) are
continuous-loop `linear` animations, and `Color(red:)` inside `DesignSystem/` only.

## Proof

- `swiftc -parse` on every touched file.
- Lint totals before and after.
- A table in your final message: each role/glyph/radius/motion mapping with its count of sites.
- **Unsure:** the `UITraitBridgedEnvironmentKey` usage, `Font.custom(_:size:relativeTo:)` fallback
  scaling, `.textRenderer`, and any site that didn't fit a rule.
