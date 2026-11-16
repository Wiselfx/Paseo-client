# M6a: composer attachments

Branch `m6a-attachments`. Shared rules: top of `docs/tickets/M3-workspace-panel.md`. Update the
Composer rows (attachment tray, add-attachment menu, attachment actions) in `docs/PARITY.md` in the
same commit. You may edit the **composer section** of `Chat/ClaudeChatView.swift`,
`Chat/ComposerQueue.swift`, new PaseoUI files. Store: T14's `ConversationStore.upload(...)`
(`PaseoStore/ConversationUpload.swift`) and T12's `sendWithAttachments`. Reference copy/flow:
`docs/research/01-app-features.md:78-83`, upstream `packages/app/src/composer/` (`actions.ts:148`).

1. **Add menu**: the composer's existing "+" opens a menu: Photo Library (`PhotosPicker`, multi),
   Camera (if available), Files (`fileImporter`, any type), and "Mention a file" (inserts `@` and
   focuses; the panel's Files page already does Mention in chat). Paste of an image from the
   pasteboard attaches it (`PasteButton` or `.onPasteCommand` where available; skip if fiddly and
   say so).
2. **Tray**: pills above the text field inside the composer card: image thumbnails (56 pt, 10 pt
   radius) or file pills (doc icon, name, size), each with a remove "x"; while uploading a thin
   progress ring on the pill (store progress); failed pill shows a retry. Images are downscaled
   to max 2048 px JPEG 0.85 before upload (HEIC → JPEG). 50 MiB limit message from the store.
3. **Send**: uploads happen when attached (not at send), so send is instant; send is disabled
   while any upload is in flight, then goes through `sendWithAttachments`. Queued messages (M8b)
   may carry attachments only if trivial; otherwise queue is disabled while the tray is non-empty
   (say which).
4. User bubble shows sent attachments: small thumbnails / file pills under the text (if the
   timeline's user message carries them; check the store, else say so).

Commit "M6a: composer attachments", don't push. Final message: what changed, store gaps,
unsure-compile spots (Photos/UniformTypeIdentifiers APIs especially).
