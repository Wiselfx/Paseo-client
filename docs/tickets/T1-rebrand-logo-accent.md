# T1: rebrand: Paseo butterfly instead of the Claude logo, Paseo accent as default

Read `AGENTS.md`, then `docs/tickets/_P-common.md` (upstream first, no invention, never push, one commit per part), then this file.

## Part A: the logo
Replace every use of the Claude logo with Paseo's butterfly, as upstream draws it.
- Upstream: `packages/app/src/components/icons/paseo-logo.tsx` (the single path, 700x700 viewBox; same path as
  `packages/app/assets/images/butterfly-green.svg` and `butterfly-white.svg`), used by the splash
  (`screens/startup-splash-screen.tsx`, 96 pt, with the shimmer: a light band sweeping across the logo, `SHIMMER_DURATION_MS` 1800, repeating),
  the welcome screen (`components/welcome-screen.tsx:266`, 96 pt), the open-project screen (`screens/open-project-screen.tsx:72`, 52 pt) and onboarding.
- Ours: find every place the Claude mark is drawn. Start with `Packages/PaseoUI/Sources/PaseoUI/Resources/Assets.xcassets/ClaudeLogo.imageset`,
  `ClaudeMark.imageset`, then grep `ClaudeLogo`, `ClaudeMark`, `"What shall we build?"` (the new-session hero in `Draft/DraftChatView.swift`),
  the welcome screen, the connect screen, the splash/launch screen and the loading states. Put the butterfly where the Claude mark was, at upstream's size
  for that screen.
- Add the butterfly as a vector asset (template image, tinted by the foreground colour) built from upstream's SVG path. Do not copy the SVG file verbatim if
  its licence needs a note: check `/home/paseo/dev/paseo-upstream-ref/LICENSE` and keep a one-line credit in the asset's README or in `THIRD_PARTY_NOTICES`
  if one exists.
- Animation: on the splash and while a new session hero is on screen at idle, port upstream's shimmer (a highlight sweeping left to right across the
  butterfly, 1.8 s, repeating). Use `Motion.resolved(reduceMotion:)`; with Reduce Motion it stays still. Do not invent other animations.
- Delete the Claude logo assets and any code that is now unused (the owner's rule: unused goes). Do NOT touch the crab sprite sheets (`Resources/Crab`).
- The app icon is out of scope: list in your final message where it lives and what it shows.

## Part B: accent
`ClaudeAccent` has `.claude` and `.paseo` (`DesignSystem/ClaudeAppearance.swift`). Make `.paseo` the default everywhere the default is named:
`Palette.swift` (`AccentTrait` / `AccentKey` `defaultValue`), `App/Sources/RootView.swift` (`@AppStorage` default and the fallback),
`Settings/GeneralPage.swift`. Keep the other accent selectable. Existing users who never chose an accent get `.paseo`; someone who chose `Claude`
explicitly keeps it (check how the stored value is read: an absent key must now mean Paseo).
Do not rename the enum or its cases in this ticket.

## Done
`swiftc -parse` on every edited Swift file; check no reference to a deleted asset remains (grep). Commits: `T1.A butterfly logo`, `T1.B Paseo accent default`.
Final message: where the butterfly now shows, what was deleted, parse results, doubts.
