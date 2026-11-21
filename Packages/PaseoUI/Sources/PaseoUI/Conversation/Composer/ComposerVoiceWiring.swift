#if canImport(UIKit)
import PaseoStore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// M15: realtime voice wiring. The engine feeds the store (mic PCM + level), the store feeds the
/// engine (next chunks + stop signals). Capture start/stop is driven by the phase.
struct ComposerVoiceWiring: ViewModifier {
    let controller: ChatController?

    func body(content: Content) -> some View {
        if let controller {
            Wired(content: content, controller: controller)
        } else {
            content
        }
    }

    private struct Wired<C: View>: View {
        let content: C
        let controller: ChatController

        /// One line per voice-mode run, at the first chunk the daemon sends back.
        @State private var firstReplyLogged = false

        var body: some View {
            content
                .task {
                    // The composer can appear while the lane is already waiting; `.onChange`
                    // never fires for the initial value. The engine is built only when voice needs it.
                    if voice.isThinkingToneExpected {
                        bind()
                        controller.voiceEngine.startThinkingTone()
                    }
                    // Same reason: capture is started from the same place the callbacks are
                    // bound, so a composer opened on a live lane still records (D2 §4).
                    if voice.isVoiceMode { await startCapture() }
                }
                .onChange(of: voice.lastPlaybackError) { _, message in
                    guard let message else { return }
                    VoiceLog.log.error("playback: \(message, privacy: .public)")
                }
                .onChange(of: voice.error) { _, message in
                    guard let message else { return }
                    VoiceLog.log.error("lane: \(message, privacy: .public)")
                    // A lane that was up and then failed (a resync the daemon refused, a stop
                    // that errored) used to fail silently: the bar just disappeared. A start
                    // refusal is already toasted by `toggleVoiceMode`.
                    if voice.isVoiceMode || voice.phase != .disabled {
                        controller.showToast(message)
                    }
                }
                .onChange(of: voice.isSpeaking) { _, speaking in
                    VoiceLog.log.info("daemon VAD: speaking=\(speaking)")
                }
                .onChange(of: voice.isMuted) { _, muted in
                    // Muting clears the meter, like the store's own telemetry reset.
                    if muted { controller.voiceEngineIfCreated?.meter.reset() }
                }
                .onChange(of: voice.phase) { _, phase in
                    VoiceLog.log.info(
                        "lane phase: \(String(describing: phase), privacy: .public)")
                    switch phase {
                    // Only `.listening` needs a capture start: the engine keeps recording through
                    // `.waiting` and `.playing` (the daemon needs the mic for barge-in), so a
                    // start on every phase change was three Tasks that all returned at the
                    // engine's guard.
                    case .listening:
                        Task { await startCapture() }
                    default:
                        controller.voiceEngineIfCreated?.stopCapture()
                        UIApplication.shared.isIdleTimerDisabled = false
                    }
                }
                .onChange(of: voice.nextAudioChunk) { _, chunk in
                    guard let chunk else { return }
                    if !firstReplyLogged {
                        firstReplyLogged = true
                        VoiceLog.log.info(
                            "reply: first \(chunk.data.count)-byte chunk (\(chunk.format, privacy: .public))")
                    }
                    bind()
                    controller.voiceEngine.enqueue(chunk) { ok in
                        if ok {
                            voice.didPlayChunk(id: chunk.id)
                        } else {
                            voice.didFailChunk(id: chunk.id)
                        }
                    }
                }
                .onChange(of: voice.playbackStopRequested) { _, _ in
                    controller.voiceEngineIfCreated?.stopPlayback()
                }
                // M15: the thinking tone (upstream `reconcileCue`): only while the lane is waiting
                // for a reply and the daemon hears no speech. Timing lives in the engine.
                .onChange(of: voice.isThinkingToneExpected) { _, expected in
                    if expected {
                        bind()
                        controller.voiceEngine.startThinkingTone()
                    } else {
                        controller.voiceEngineIfCreated?.stopThinkingTone()
                    }
                }
                .onDisappear {
                    Task { await voice.stop() }
                    controller.voiceEngineIfCreated?.stopThinkingTone()
                    controller.voiceEngineIfCreated?.stopCapture()
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }

        private var voice: VoiceModeSession { controller.session.voiceSession }

        private func bind() {
            controller.voiceEngine.onCapturePCM = { data in
                voice.handleCapturePCM(data)
            }
            controller.voiceEngine.onVolumeLevel = { level in
                voice.handleCaptureVolume(level)
            }
            controller.voiceEngine.onInterruption = {
                voice.setMuted(true)
            }
        }

        private func startCapture() async {
            guard voice.isVoiceMode else { return }
            bind()
            do {
                // The lane can stop while a call suspends (the permission alert, the engine's
                // start): the phase handler has already stopped capture by then, and nothing
                // would stop what this resumes into. Check again after each suspension.
                try await controller.voiceEngine.requestMicPermission()
                guard voice.isVoiceMode, !Task.isCancelled else { return }
                try await controller.voiceEngine.startCapture()
                guard voice.isVoiceMode else {
                    controller.voiceEngine.stopCapture()
                    return
                }
                UIApplication.shared.isIdleTimerDisabled = true
            } catch {
                controller.showToast(error.localizedDescription)
                await voice.stop()
            }
        }
    }
}
#endif
