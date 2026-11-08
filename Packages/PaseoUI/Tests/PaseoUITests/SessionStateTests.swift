import Testing
@testable import PaseoUI

@Test func blankSendAndReentrantSendAreIgnored() {
    var state = SessionState()
    state.reduce(.send("  \n"))
    #expect(state.messages.isEmpty)
    state.reduce(.send("hello"))
    state.reduce(.send("duplicate"))
    #expect(state.messages.count == 1)
    #expect(state.phase == .streaming)
}
@Test func streamingStopRejectsLateChunksAndRetainsPartialResponse() {
    var state = SessionState()
    state.draft = "hello"
    state.reduce(.send(state.draft))
    #expect(state.draft.isEmpty)
    let responseID = state.responseID!
    state.appendResponse("Hello", responseID: responseID)
    state.reduce(.stop)
    state.appendResponse(" late", responseID: responseID)
    #expect(state.messages.last?.text == "Hello")
    #expect(state.phase == .idle)
}
@Test func dictationCancelRestoresDraftAcrossPause() {
    var state = SessionState()
    state.draft = "Original draft"
    state.reduce(.startDictation)
    state.transcript = "new words"
    state.reduce(.stopDictation)
    #expect(state.phase == .recordingPaused)
    state.reduce(.cancelDictation)
    #expect(state.draft == "Original draft")
    #expect(state.transcript.isEmpty)
    #expect(state.phase == .idle)
}
@Test func dictationCommitCombinesWithoutSending() {
    var state = SessionState()
    state.draft = "Original"
    state.reduce(.startDictation)
    state.transcript = "new words"
    state.reduce(.commitDictation)
    #expect(state.draft == "Original new words")
    #expect(state.messages.isEmpty)
    #expect(state.canSend)
}
@Test func cannotRecordDuringResponse() {
    var state = SessionState()
    state.reduce(.send("Hi"))
    state.reduce(.startDictation)
    #expect(state.phase == .streaming)
}
@Test func attachmentsDeduplicateAndCanSendWithoutText() {
    var state = SessionState()
    state.reduce(.attach("photo.jpg"))
    state.reduce(.attach("photo.jpg"))
    #expect(state.attachments.count == 1)
    #expect(state.canSend)
    state.reduce(.removeAttachment("photo.jpg"))
    #expect(!state.canSend)
}
@Test func staleChunksAndCompletionCannotContaminateANewerResponse() {
    var state = SessionState()
    state.reduce(.send("First"))
    let first = state.responseID!
    state.reduce(.stop)
    state.reduce(.send("Second"))
    let second = state.responseID!
    #expect(first != second)
    state.appendResponse("stale", responseID: first)
    state.finishResponse(responseID: first)
    #expect(state.messages.count == 2)
    #expect(state.phase == .streaming)
    state.appendResponse("Current", responseID: second)
    state.finishResponse(responseID: second)
    #expect(state.messages.last?.text == "Current")
    #expect(state.phase == .idle)
}
@Test func silentDictationStopReturnsIdleAndPreservesPriorDraft() {
    var state = SessionState()
    state.draft = "Keep draft"
    state.reduce(.startDictation)
    state.transcript = " \n "
    state.reduce(.stopDictation)
    #expect(state.phase == .idle)
    #expect(state.draft == "Keep draft")
    #expect(state.transcript.isEmpty)
    #expect(state.dictationLevels.isEmpty)
}
@Test func waveformNormalizesMalformedLevelsAndNeverExceedsItsUIBounds() {
    var state = SessionState()
    state.reduce(.startDictation)
    state.dictationLevels = [-1, 0, 0.5, 3, .nan, .infinity, -.infinity]
    #expect(state.dictationLevels == [0, 0, 0.5, 1, 0, 0, 0])
    let heights = DictationWaveformMetrics.barHeights(for: state.dictationLevels, count: 7)
    #expect(heights == [2.6, 2.6, 12, 24, 2.6, 2.6, 2.6])
    #expect(DictationWaveformMetrics.barHeights(for: [], count: 3) == [2.6, 2.6, 2.6])
    #expect(DictationWaveformMetrics.barHeights(for: [1], count: -1).isEmpty)
    #expect(DictationWaveformMetrics.barHeights(for: [1], count: 999).count == 256)
}
@Test func waveformLevelsClearOnCancellationCommitAndNewSession() {
    var state = SessionState()
    state.reduce(.startDictation)
    state.dictationLevels = [1, 0.5]
    state.reduce(.cancelDictation)
    #expect(state.dictationLevels.isEmpty)
    state.reduce(.startDictation)
    state.dictationLevels = [0.5]
    state.transcript = "Hello"
    state.reduce(.commitDictation)
    #expect(state.dictationLevels.isEmpty)
    state.reduce(.startDictation)
    state.dictationLevels = Array(repeating: 0.7, count: 300)
    #expect(state.dictationLevels.count == 256)
    state.reduce(.newSession)
    #expect(state.dictationLevels.isEmpty)
    #expect(state.phase == .idle)
}

@Test func voiceEntryExitPreservesConversationDraftAndAttachments() {
    var state = SessionState()
    state.messages = [.init(role: .user, text: "Hello"), .init(role: .assistant, text: "Hi")]
    state.draft = "Draft"
    state.attachments = ["notes.pdf"]
    let messages = state.messages
    state.reduce(.startVoice)
    #expect(state.voiceActive)
    state.reduce(.toggleVoiceInput)
    state.reduce(.toggleVoiceOutput)
    #expect(!state.voiceInputEnabled)
    #expect(state.voiceOutputMuted)
    state.reduce(.endVoice)
    #expect(!state.voiceActive)
    #expect(state.voiceInputEnabled)
    #expect(!state.voiceOutputMuted)
    #expect(state.messages == messages)
    #expect(state.draft == "Draft")
    #expect(state.attachments == ["notes.pdf"])
}
@Test func codeFiltersEveryStatusWithoutChangingInjectedSessions() {
    var state = CodeState()
    state.sessions = [
        .init(id: "idle", title: "Idle"), .init(id: "work", title: "Working", status: .working),
        .init(id: "input", title: "Needs input", status: .needsInput),
        .init(id: "review", title: "Review", status: .readyForReview),
        .init(id: "done", title: "Done", status: .completed),
        .init(id: "archived", title: "Archived", status: .working, archived: true)
    ]
    let original = state.sessions
    for (filter, ids): (CodeFilter, [String]) in [
        (.all, ["idle", "work", "input", "review", "done"]), (.working, ["work"]), (.needsInput, ["input"]),
        (.readyForReview, ["review"]), (.completed, ["done"]), (.archived, ["archived"])
    ] {
        state.reduce(.selectFilter(filter))
        #expect(state.visibleSessions.map(\.id) == ids)
        #expect(state.sessions == original)
    }
}
@Test func codeHostIntentsDoNotCreateSessionsOrDevices() {
    var state = CodeState()
    let original = state
    for action: CodeAction in [.addDevice, .openSession("missing"), .openDevice("missing"), .search] {
        state.reduce(action)
    }
    #expect(state == original)
}
@Test func routineBackPreservesDraftButCancelDiscardsUnsavedForm() {
    var state = RoutineState()
    state.reduce(.edit(.name, "Ignored"))
    #expect(state.draft.name.isEmpty)
    state.reduce(.newRoutine)
    state.reduce(.edit(.description, "Review changes"))
    state.reduce(.manualSetup)
    state.reduce(.edit(.name, "Morning review"))
    state.reduce(.edit(.instructions, "Review sample changes"))
    state.reduce(.addSchedule)
    state.reduce(.backToDescription)
    #expect(state.description == "Review changes")
    #expect(state.draft.name == "Morning review")
    state.reduce(.manualSetup)
    #expect(state.canCreate)
    let before = state
    state.reduce(.create(state.draft))
    state.reduce(.draftRoutine("Review changes"))
    #expect(state == before)
    state.reduce(.cancel)
    #expect(state.editor == nil)
    #expect(state.description.isEmpty)
    #expect(state.draft == RoutineDraft())
    #expect(!state.canCreate)
}
@Test func routineScheduleDefaultsClampsAndRemovalAreLocal() {
    var state = RoutineState()
    state.reduce(.addSchedule)
    #expect(state.draft.schedule == nil)
    state.reduce(.newRoutine)
    state.reduce(.manualSetup)
    state.reduce(.addSchedule)
    #expect(state.draft.schedule?.repeats == .daily)
    #expect(state.draft.schedule?.hour == 1)
    #expect(state.draft.schedule?.minute == 0)
    state.reduce(.setTime(hour: 24, minute: -1))
    #expect(state.draft.schedule?.hour == 1)
    state.reduce(.setTime(hour: 23, minute: 59))
    state.reduce(.setRepeat(.weekdays))
    #expect(state.draft.schedule?.minute == 59)
    state.reduce(.toggleSchedule)
    #expect(!state.scheduleExpanded)
    state.reduce(.removeSchedule)
    state.reduce(.setTime(hour: 2, minute: 0))
    #expect(state.draft.schedule == nil)
    state.reduce(.addSchedule)
    #expect(state.scheduleExpanded)
    #expect(state.draft.schedule?.repeats == .daily)
}

@Test func routineFilterDoesNotChangeUnsavedDraftOrSchedule() {
    var state = RoutineState()
    state.reduce(.newRoutine)
    state.reduce(.manualSetup)
    state.reduce(.edit(.name, "Keep"))
    state.reduce(.addSchedule)
    let draft = state.draft
    state.reduce(.selectFilter(.active))
    #expect(state.filter == .active)
    #expect(state.draft == draft)
    state.reduce(.selectFilter(.inactive))
    state.reduce(.cancel)
    #expect(state.filter == .inactive)
    #expect(state.editor == nil)
}

@Test func codeDraftChoicesRemainSeparateFromOrdinaryChatAndDoNotSubmitWork() {
    var state = SessionState()
    state.reduce(.openCode)
    state.reduce(.code(.newSession))
    state.reduce(.code(.editor(.edit("   "))))
    #expect(!state.code.draft.canSubmit)
    state.reduce(.code(.editor(.edit("Sample task"))))
    state.reduce(.code(.editor(.selectModel(.haiku))))
    state.reduce(.code(.editor(.selectEffort(.ultracode))))
    #expect(state.code.draft.canSubmit)
    #expect(state.model == .opus)
    #expect(state.effort == .high)
    let draft = state.code.draft
    state.reduce(.code(.editor(.submit(draft))))
    #expect(state.code.draft == draft)
    #expect(state.messages.isEmpty)
    state.reduce(.code(.closeNewSession))
    state.reduce(.code(.newSession))
    #expect(state.code.draft.text == "Sample task")
}
@Test func connectorPermissionsValidateIDsAndStayWithinSelectedService() {
    var state = CodeConnectorState()
    state.connectors = [
        .init(
            id: "a", name: "A", connected: true,
            tools: [.init(id: "one", name: "One"), .init(id: "two", name: "Two", permission: .blocked)]),
        .init(id: "b", name: "B", connected: true, tools: [.init(id: "one", name: "One")])
    ]
    #expect(state.connectors[0].commonPermission == nil)
    let initial = state
    state.reduce(.permission(connector: "unknown", tool: nil, value: .allowed))
    state.reduce(.permission(connector: "a", tool: "unknown", value: .allowed))
    #expect(state == initial)
    state.reduce(.permission(connector: "a", tool: "one", value: .blocked))
    #expect(state.connectors[0].commonPermission == .blocked)
    #expect(state.connectors[1].commonPermission == .approval)
    state.reduce(.permission(connector: "a", tool: nil, value: .allowed))
    #expect(state.connectors[0].commonPermission == .allowed)
}
@Test func connectorHostIntentsCannotConnectOrMutateDisconnectedTools() {
    var state = CodeConnectorState()
    state.connectors = [.init(id: "sample", name: "Sample", tools: [.init(id: "one", name: "One")])]
    let original = state
    state.reduce(.add)
    state.reduce(.connect("sample"))
    state.reduce(.permission(connector: "sample", tool: nil, value: .allowed))
    #expect(state == original)
    state.reduce(.discovery(true))
    #expect(state.discovery)
    #expect(state.connectors == original.connectors)
}
