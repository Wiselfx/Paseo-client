# T14: file upload over binary frames (backend)

Branch `t14-file-upload`. Backend only: PaseoProtocol + PaseoKit + PaseoStore + tests + probe.
Follow `docs/tickets/PHASE2-CONVENTIONS.md` (fixtures first, sandbox only, tolerant decoding,
errors as observable properties, a probe subcommand). No background tasks, no subagents, don't
end your turn while waiting.

T12 added attachments but not byte upload: `file.upload.request` + binary `FileBegin`/`FileChunk`/
`FileEnd` frames (spec `docs/research/04-protocol-agents-permissions-settings.md` §10.3; upstream
source in `/home/paseo/dev/paseo-reference`: find the binary frame codec and `file.upload` handling
on both server and app side and cite file:line; the app's flow is `app/composer/actions.ts:148`).

1. PaseoKit: a public way to send a binary frame (`DaemonClient` gains a binary send; implement in
   `DaemonConnection` and `FakeDaemonClient`). Keep the existing API unchanged otherwise.
2. PaseoProtocol: the file frame codec (exact byte layout from upstream, with tests against bytes
   produced by the upstream codec: capture them with a small node script under `Tools/` and save
   as fixtures), and `FileUploadRequest`/response types.
3. PaseoStore: `ConversationStore` (new file, extension or helper type) `upload(data:fileName:mimeType:)
   async -> UploadedFileAttachment?` with progress as observable state, 128 KiB chunks, cancel,
   and the app-side size limit from upstream. Then sending a message with uploaded files through
   T12's `sendWithAttachments`.
4. Probe: `paseo-probe upload <agentId> <localFile>` against the sandbox agent
   `1c51ee58-765c-4f8d-bf27-7009338b361e` (`/tmp/fixture-sandbox`), sending a tiny text file and
   asking the agent to print its first line; show it worked.

Done means `rm -rf Packages/PaseoCore/.build && swift build --build-tests && swift test` green, no
warnings in your files. Commit "T14: file upload", don't push. Final message: byte layout
summary with upstream citations, test counts, live probe output, anything unsure.
