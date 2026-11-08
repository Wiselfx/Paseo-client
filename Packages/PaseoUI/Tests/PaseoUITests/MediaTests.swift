import Testing
@testable import PaseoUI

private let photo = ClaudeMedia(id: "one", fileName: "Garden.png", aspectRatio: 0.97)
@Test func mediaSelectionRejectsMissingItemsAndDeduplicatesAttachment() {
    var media = ClaudeMediaState()
    media.recent = [photo]
    media.reduce(.toggleRecent("missing"))
    #expect(media.selected.isEmpty)
    media.reduce(.toggleRecent(photo.id))
    #expect(media.selected == [photo])
    media.reduce(.toggleRecent(photo.id))
    #expect(media.selected.isEmpty)
    media.reduce(.toggleRecent(photo.id))
    media.reduce(.attachSelected)
    media.reduce(.toggleRecent(photo.id))
    media.reduce(.attachSelected)
    #expect(media.draft == [photo])
    #expect(media.selectedIDs.isEmpty)
    media.reduce(.toggleRecent(photo.id))
    media.reduce(.cancelSelection)
    #expect(media.selected.isEmpty)
}
@Test func selectionRemovedByHostCannotBecomeDraft() {
    var media = ClaudeMediaState()
    media.recent = [photo]
    media.reduce(.toggleRecent(photo.id))
    media.recent = []
    media.reduce(.attachSelected)
    #expect(media.draft.isEmpty)
}
@Test func mediaSendPreservesPixelsMetadataWithoutFilenameText() {
    var state = SessionState()
    state.media.draft = [photo]
    #expect(state.canSend)
    state.reduce(.send(""))
    #expect(state.messages.first?.media == [photo])
    #expect(state.messages.first?.text == "")
    #expect(state.media.draft.isEmpty)
    let token = state.responseID!
    state.reduce(.newSession)
    state.appendResponse("late", responseID: token)
    #expect(state.messages.isEmpty)
}
@Test func mediaViewerHideCloseRemoveAndSessionReset() {
    var state = SessionState()
    state.media.recent = [photo]
    state.media.draft = [photo]
    state.reduce(.media(.open(photo)))
    state.reduce(.media(.toggleControls))
    #expect(!state.media.controlsVisible)
    state.reduce(.media(.close))
    #expect(state.media.viewer == nil)
    #expect(state.media.controlsVisible)
    state.reduce(.media(.toggleControls))
    #expect(state.media.controlsVisible)
    state.reduce(.media(.open(photo)))
    state.reduce(.media(.removeDraft(photo.id)))
    #expect(state.media.viewer == nil)
    state.reduce(.media(.open(photo)))
    state.reduce(.newSession)
    #expect(state.media.viewer == nil)
    #expect(state.media.recent == [photo])
}
@Test func mediaInvalidAspectRatiosAreSafeEvenAfterHostMutation() {
    for value in [Double.nan, .infinity, -.infinity, 0, -1] {
        var item = ClaudeMedia(id: "bad", fileName: "bad", aspectRatio: value)
        #expect(item.displayAspectRatio == 1)
        item.aspectRatio = value
        #expect(item.displayAspectRatio == 1)
    }
}

@Test func videoKindAndFilenamePresentationRemainTyped() {
    let video = ClaudeMedia(id: "v", fileName: "A.long.video.mp4", kind: .video)
    #expect(video.kind == .video)
    #expect(video.fileExtension == "MP4")
    #expect(video.fileStem == "A.long.video")
    #expect(photo.kind == .image)
}
@Test func videoViewerDoesNotInheritImageToolbarTogglingOrPerformDownloads() {
    var media = ClaudeMediaState()
    let video = ClaudeMedia(id: "v", fileName: "movie.mp4", kind: .video)
    media.reduce(.open(video))
    media.reduce(.toggleControls)
    #expect(media.controlsVisible)
    let previous = media
    media.reduce(.download(video))
    media.reduce(.videoViewerAppeared(video))
    media.reduce(.videoViewerDisappeared(video))
    #expect(media == previous)
    media.reduce(.close)
    #expect(media.viewer == nil)
}
