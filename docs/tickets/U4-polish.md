# U4: Formatting and small polish (Crouton)

Branch `u4-polish`. Read `_U-common.md` first. Small, mechanical, self-contained. Spec: §0.1, §0.2, §4.1, §5, §6 (sizes). Audit: B1, B3, B5, B6, B7 (tint only), B8 (sizes only), A9, and the Sweep sections of both audits for colors and number formatting.

## Work

1. **`PaseoFormat`** (new file `Packages/PaseoUI/Sources/PaseoUI/PaseoFormat.swift`) per §0.2. Replace **every** display number, percent and byte formatting in PaseoUI and App with it. B5 lists the sites; grep again for `.formatted(`, `NumberFormatter`, `ByteCountFormatter`, and `\(` interpolations of counts in `Text`. List every replaced site in your final message.
2. **Cron describer:** a pure function in PaseoCore (`PaseoStore/CronDescription.swift`) per the §5 table, with exhaustive unit tests.
   - Times in the device time zone. Convert from the schedule's time zone; take "now" and the time zone as parameters, for tests.
   - Use it in the schedules list and detail. Drop the "Cron:" prefix; the raw expression shows in the detail page only.
3. **Colors:**
   - the composer model chip is grey (delete the `hasCustomThinking` orange branch, B1);
   - the context ring is monochrome (B3);
   - the provider toggle is `.tint(.blue)` (B7);
   - sweep for other toggles without a tint, and other orange used as state (the Sweep sections). Fix each one per §0.1 and list them.
4. **Files sizes:** folders show no size, files use `PaseoFormat.bytes`. Verify the unit the daemon sends, and cite the schema.
5. **Search sheet header:** move the Spacer inside the HStack (A9); check the other sheet headers for the same bug.

**Do not touch** `ChatTranscript.swift`, `ChatTurns.swift`, `PaseoShellView.swift` or `PaseoSidebar.swift` beyond number-formatting one-liners. Other workers own them, so keep those edits minimal.
