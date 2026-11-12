//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Observation
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
@Observable
final class InputViewModel {

    var text = "" {
        didSet { updateDraftState() }
    }
    var attachments = InputViewAttachments() {
        didSet { updateDraftState() }
    }
    var state: InputViewState = .empty

    var showPhotoPicker = false
    var showCameraPicker = false
    var showCameraUnavailableAlert = false
    var showDocumentPicker = false
    var showLocationPicker = false
    var selectedPhotoItems: [PhotosPickerItem] = []
    var isImportingMedia = false

    var showActivityIndicator = false

    @ObservationIgnored var recordingPlayer: RecordingPlayer?
    @ObservationIgnored var didSendMessage: ((DraftMessage) -> Void)?

    @ObservationIgnored private var recorder = Recorder()

    @ObservationIgnored private var saveEditingClosure: ((String) -> Void)?
    @ObservationIgnored private var mediaImportGeneration = 0
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    @ObservationIgnored private var recordingProgressTask: Task<Void, Never>?

    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) async {
        await recorder.setRecorderSettings(recorderSettings)
    }

    func recordingPlaybackDidFinish() {
        state = .hasRecording
    }

    func stopRecordingWhenViewDisappears() {
        recordingStartTask?.cancel()
        recordingStartTask = nil
        recordingProgressTask?.cancel()
        recordingProgressTask = nil
        recordingPlayer?.pause()

        if state == .isRecordingTap || state == .isRecordingHold || state == .waitingForRecordingPermission {
            if attachments.recording?.url != nil {
                state = .hasRecording
            } else {
                attachments.recording = nil
                updateDraftState()
            }
        }

        Task { await recorder.stopRecording() }
    }

    func reset() {
        recordingStartTask?.cancel()
        recordingStartTask = nil
        recordingProgressTask?.cancel()
        recordingProgressTask = nil
        text = ""
        attachments = InputViewAttachments()
        state = .empty
        showPhotoPicker = false
        showCameraPicker = false
        selectedPhotoItems = []
        mediaImportGeneration += 1
        isImportingMedia = false
        showDocumentPicker = false
        showLocationPicker = false
        saveEditingClosure = nil
        updateDraftState()
    }

    func send() {
        Task {
            recordingProgressTask?.cancel()
            recordingProgressTask = nil
            await recorder.stopRecording()
            recordingPlayer?.reset()
            sendMessage()
        }
    }

    func edit(_ closure: @escaping (String) -> Void) {
        saveEditingClosure = closure
        state = .editing
    }

    func inputViewAction() -> (InputViewAction) -> Void {
        { [weak self] in
            self?.inputViewActionInternal($0)
        }
    }

    private func inputViewActionInternal(_ action: InputViewAction) {
        switch action {
        case .photo:
            showPhotoPicker = true
        case .add, .camera:
            if AVCaptureDevice.default(for: .video) != nil {
                showCameraPicker = true
            } else {
                showCameraUnavailableAlert = true
            }
        case .document:
            showDocumentPicker = true
        case .location:
            showLocationPicker = true
        case .send:
            send()
        case .recordAudioTap:
            Task {
                state = await recorder.isAllowedToRecordAudio ? .isRecordingTap : .waitingForRecordingPermission
                recordAudio()
            }
        case .recordAudioHold:
            Task {
                state = await recorder.isAllowedToRecordAudio ? .isRecordingHold : .waitingForRecordingPermission
                recordAudio()
            }
        case .recordAudioLock:
            state = .isRecordingTap
        case .stopRecordAudio:
            Task {
                recordingProgressTask?.cancel()
                recordingProgressTask = nil
                await recorder.stopRecording()
                if let _ = attachments.recording {
                    state = .hasRecording
                }
                recordingPlayer?.reset()
            }
        case .deleteRecord:
            Task {
                recordingProgressTask?.cancel()
                recordingProgressTask = nil
                await recorder.stopRecording()
                attachments.recording = nil
            }
        case .playRecord:
            state = .playingRecording
            if let recording = attachments.recording {
                recordingPlayer?.play(recording)
            }
        case .pauseRecord:
            state = .pausedRecording
            recordingPlayer?.pause()
        case .saveEdit:
            saveEditingClosure?(text)
            reset()
        case .cancelEdit:
            reset()
        }
    }

    func importSelectedPhotos(_ items: [PhotosPickerItem]) async {
        selectedPhotoItems = []
        guard !items.isEmpty else { return }

        mediaImportGeneration += 1
        let generation = mediaImportGeneration
        isImportingMedia = true

        let importedMedia = await NativeMediaImporter.importItems(items)
        defer {
            if generation == mediaImportGeneration {
                isImportingMedia = false
            }
        }
        guard !Task.isCancelled, generation == mediaImportGeneration else { return }

        attachments.medias.append(contentsOf: importedMedia)
    }

    private func recordAudio() {
        recordingStartTask?.cancel()
        recordingStartTask = Task { @MainActor [weak self, recorder] in
            guard let self else { return }
            guard !(await recorder.isRecording), !Task.isCancelled else { return }
            attachments.recording = Recording()
            guard let session = await recorder.startRecording() else {
                if await recorder.isRecording { return }
                attachments.recording = nil
                updateDraftState()
                if state == .waitingForRecordingPermission {
                    state = .empty
                }
                return
            }
            guard !Task.isCancelled else {
                await recorder.stopRecording()
                return
            }
            if state == .waitingForRecordingPermission {
                state = .isRecordingTap
            }
            attachments.recording?.url = session.url

            recordingProgressTask = Task { @MainActor [weak self] in
                for await progress in session.progress {
                    guard !Task.isCancelled, let self,
                          self.attachments.recording?.url == session.url else { return }
                    self.attachments.recording?.duration = progress.duration
                    self.attachments.recording?.waveformSamples = progress.waveformSamples
                }
            }
        }
    }
}

private extension InputViewModel {

    func updateDraftState() {
        guard state != .editing else { return }
        let hasAttachments = !attachments.medias.isEmpty
            || !attachments.documents.isEmpty
            || attachments.staticLocation != nil
            || attachments.liveLocation != nil
        if !text.isEmpty || hasAttachments {
            state = .hasTextOrMedia
        } else if attachments.recording == nil {
            state = .empty
        }
    }

}

private extension InputViewModel {

    func sendMessage() {
        showActivityIndicator = true
        // live location shares need a stable id upfront so subsequent location updates can find this message again
        let messageId = (attachments.liveLocation != nil) ? UUID().uuidString : nil
        let draft = DraftMessage(
            id: messageId,
            text: text,
            medias: attachments.medias,
            documents: attachments.documents,
            staticLocation: attachments.staticLocation,
            liveLocation: attachments.liveLocation,
            recording: attachments.recording,
            replyMessage: attachments.replyMessage,
            createdAt: Date()
        )
        didSendMessage?(draft)
        showActivityIndicator = false
        reset()
    }
}
