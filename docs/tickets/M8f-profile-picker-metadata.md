# M8f: profile picker in new agent, metadata generation setting

Branch `m8f-profile-picker`. UI rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
Agents & models / host settings rows in `docs/PARITY.md` in the same commit. You may edit
`Chat/ClaudeNewAgentSheet.swift`, `Settings/*` (yours from M4d), `Chat/PaseoSettingsView.swift`
(one row), `HostSettingsStore.swift` (additive), new files. Not `Conversation/*` or `Sidebar/*`.

1. **Profile picker** in the new-agent sheet (only when profiles exist): a quiet "Profile" row
   whose choice prefills provider, model, mode, thinking and feature values (applied once at
   creation, like upstream); the user can still change fields after picking; "None" clears.
2. **Metadata generation** setting (doc 04 §12.1, config `metadataGeneration`): Settings → host →
   a row choosing the provider/model used for titles and branch names, written as a config patch
   (deep-partial, only that key). Gate as upstream does.

swiftc -parse every touched file; PaseoCore rebuild+tests if touched. Never write the real host
config in testing (fixtures/fakes only). Commit "M8f: profile picker and metadata", don't push.
Final message: what changed, store gaps, unsure-compile spots.
