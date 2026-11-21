#if canImport(UIKit)
import PaseoStore
import SwiftUI

/// What the schedule editor lets the person change, as one value. The page keeps it twice, as the
/// live fields and as the baseline it opened with, so "dirty" is `fields != baseline`. The
/// baseline is `@State` too: a plain `let` would be recomputed on every re-init of the page and
/// could drift from what the person actually started with. Validation and the save payloads live
/// here, not in the view, so they have no UI dependency.
struct ScheduleEditorFields: Equatable {
    var name = ""
    var prompt = ""
    var cron = CadencePreset.all[0].expression
    var timezone = ""
    /// The max-runs field's text, empty for unlimited. It stays text, as the field always was, so a
    /// value that is not a whole number remains visible and blocks Save.
    var maxRunsText = ""
    var cwd = ""
    var providerId = ""
    var modelId = ""
    var modeId = ""
    var thinkingId = ""

    /// A new schedule opens on the first workspace and the first ready provider; a stored one
    /// opens on its own values. A cadence that is not cron has no cron or timezone to edit.
    init(seed: ClaudeSchedulesView.EditorSeed, defaultCwd: String, defaultProviderId: String) {
        cwd = defaultCwd
        providerId = defaultProviderId
        guard let stored = seed.stored else { return }
        let summary = stored.summary
        name = summary.name ?? ""
        prompt = summary.prompt
        maxRunsText = summary.maxRuns.map(String.init) ?? ""
        switch summary.cadence {
        case .cron(let expression, let storedTimezone):
            cron = expression
            timezone = storedTimezone ?? ""
        default:
            cron = ""
            timezone = ""
        }
        if let config = summary.target.newAgentConfig {
            cwd = config.cwd
            providerId = config.provider
            modelId = config.model ?? ""
            modeId = config.modeId ?? ""
            thinkingId = config.thinkingOptionId ?? ""
        } else {
            cwd = ""
            providerId = ""
        }
    }

    // MARK: Validation

    var promptIsEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var cronIsInvalid: Bool { !ScheduleWords.isValid(cron: cron) }
    /// The parsed max runs: nil when the field is empty (unlimited) or not a whole number.
    var maxRuns: Int? { Int(trimmedMaxRunsText) }
    var maxRunsIsInvalid: Bool {
        let trimmed = trimmedMaxRunsText
        guard !trimmed.isEmpty else { return false }
        return Int(trimmed).map { $0 >= 1 } != true
    }
    private var trimmedMaxRunsText: String {
        maxRunsText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A heartbeat (or any non-cron cadence) skips the cron check and the target fields.
    func canSave(isHeartbeat: Bool, hasReadOnlyCadence: Bool) -> Bool {
        if isHeartbeat {
            return !promptIsEmpty && !maxRunsIsInvalid
                && (hasReadOnlyCadence || !cronIsInvalid)
        }
        return !promptIsEmpty && !cronIsInvalid && !maxRunsIsInvalid && !providerId.isEmpty
            && !cwd.isEmpty
    }

    // MARK: Payloads

    private var cronCadence: ScheduleCadence {
        let trimmedTimezone = timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        return .cron(
            expression: cron.trimmingCharacters(in: .whitespacesAndNewlines),
            timezone: trimmedTimezone.isEmpty ? nil : trimmedTimezone)
    }

    /// The `schedule/create` payload for a new schedule.
    var draft: ScheduleDraft {
        let config = ScheduleNewAgentConfig(
            provider: providerId, cwd: cwd,
            modeId: modeId.isEmpty ? nil : modeId,
            model: modelId.isEmpty ? nil : modelId,
            thinkingOptionId: thinkingId.isEmpty ? nil : thinkingId)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScheduleDraft(
            name: trimmedName.isEmpty ? nil : trimmedName,
            prompt: prompt, cadence: cronCadence, target: .newAgent(config),
            maxRuns: maxRuns)
    }

    /// The `schedule/update` payload: only what differs from the stored schedule.
    func edits(for stored: StoredSchedule, hasReadOnlyCadence: Bool) -> ScheduleEdits {
        let initial = stored.summary
        let namePatch = Self.patchString(name, comparedTo: initial.name ?? "")
        let promptEdit = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            == initial.prompt.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : prompt
        let maxRunsPatch = Self.patchInt(maxRunsText, comparedTo: initial.maxRuns)

        var cadenceEdit: ScheduleCadence?
        if !hasReadOnlyCadence {
            let cadence = cronCadence
            if cadence != initial.cadence { cadenceEdit = cadence }
        }

        guard let config = initial.target.newAgentConfig else {
            // A heartbeat: provider/model/mode/thinking stay untouched.
            return ScheduleEdits(
                name: namePatch, prompt: promptEdit, cadence: cadenceEdit, maxRuns: maxRunsPatch)
        }

        var newAgentConfig: ScheduleNewAgentConfigUpdate? = nil
        let providerChanged = providerId != config.provider
        let modelPatch = Self.patchString(modelId, comparedTo: config.model ?? "")
        let modePatch = Self.patchString(modeId, comparedTo: config.modeId ?? "")
        let thinkingPatch = Self.patchString(thinkingId, comparedTo: config.thinkingOptionId ?? "")
        if providerChanged || modelPatch != .unchanged || modePatch != .unchanged
            || thinkingPatch != .unchanged
        {
            newAgentConfig = ScheduleNewAgentConfigUpdate(
                provider: providerChanged ? providerId : nil,
                model: modelPatch, modeId: modePatch, thinkingOptionId: thinkingPatch)
        }

        return ScheduleEdits(
            name: namePatch, prompt: promptEdit, cadence: cadenceEdit,
            maxRuns: maxRunsPatch, newAgentConfig: newAgentConfig)
    }

    private static func patchString(_ new: String, comparedTo old: String) -> SchedulePatch<String> {
        let newTrimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldTrimmed = old.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTrimmed == oldTrimmed { return .unchanged }
        return newTrimmed.isEmpty ? .clear : .set(newTrimmed)
    }

    private static func patchInt(_ text: String, comparedTo old: Int?) -> SchedulePatch<Int> {
        let newTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = newTrimmed.isEmpty ? nil : Int(newTrimmed)
        // Invalid input can't be saved anyway.
        guard newTrimmed.isEmpty || parsed != nil else { return .unchanged }
        if parsed == old { return .unchanged }
        guard let parsed else { return .clear }
        return .set(parsed)
    }
}
#endif
