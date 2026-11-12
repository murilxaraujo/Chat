//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Combine
import SwiftUI
import PhotosUI
import AVFoundation

@MainActor
final class InputViewModel: ObservableObject {

    @Published var text = ""
    @Published var attachments = InputViewAttachments()
    @Published var state: InputViewState = .empty

    @Published var showPhotoPicker = false
    @Published var showCameraPicker = false
    @Published var showCameraUnavailableAlert = false
    @Published var showDocumentPicker = false
    @Published var showLocationPicker = false
    @Published var selectedPhotoItems: [PhotosPickerItem] = []
    @Published var isImportingMedia = false

    @Published var showActivityIndicator = false

    var recordingPlayer: RecordingPlayer?
    var didSendMessage: ((DraftMessage) -> Void)?

    private var recorder = Recorder()

    private var saveEditingClosure: ((String) -> Void)?
    private var mediaImportGeneration = 0

    private var recordPlayerSubscription: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    
    func setRecorderSettings(recorderSettings: RecorderSettings = RecorderSettings()) {
        Task {
            await self.recorder.setRecorderSettings(recorderSettings)
        }
    }

    func onStart() {
        subscribeValidation()
    }

    func onStop() {
        subscriptions.removeAll()
    }

    func reset() {
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
        subscribeValidation()
    }

    func send() {
        Task {
            await recorder.stopRecording()
            await recordingPlayer?.reset()
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
                await recorder.stopRecording()
                if let _ = attachments.recording {
                    state = .hasRecording
                }
                await recordingPlayer?.reset()
            }
        case .deleteRecord:
            Task {
                unsubscribeRecordPlayer()
                await recorder.stopRecording()
                attachments.recording = nil
            }
        case .playRecord:
            state = .playingRecording
            if let recording = attachments.recording {
                Task {
                    subscribeRecordPlayer()
                    await recordingPlayer?.play(recording)
                }
            }
        case .pauseRecord:
            state = .pausedRecording
            Task {
                await recordingPlayer?.pause()
            }
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
        guard generation == mediaImportGeneration else { return }

        attachments.medias.append(contentsOf: importedMedia)
        isImportingMedia = false
    }

    private func recordAudio() {
        let progressHandler: Recorder.ProgressHandler = { [weak self] duration, samples in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.attachments.recording?.duration = duration
                self.attachments.recording?.waveformSamples = samples
            }
        }

        Task { @MainActor [recorder] in
            if await recorder.isRecording { return }
            attachments.recording = Recording()
            let url = await recorder.startRecording(durationProgressHandler: progressHandler)
            if state == .waitingForRecordingPermission {
                state = .isRecordingTap
            }
            attachments.recording?.url = url
        }
    }
}

private extension InputViewModel {

    func validateDraft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.state != .editing else { return } // special case
            let hasAttachments = !self.attachments.medias.isEmpty || !self.attachments.documents.isEmpty || self.attachments.staticLocation != nil || self.attachments.liveLocation != nil
            if !self.text.isEmpty || hasAttachments {
                self.state = .hasTextOrMedia
            } else if self.text.isEmpty,
                      !hasAttachments,
                      self.attachments.recording == nil {
                self.state = .empty
            }
        }
    }

    func subscribeValidation() {
        $attachments.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)

        $text.sink { [weak self] _ in
            self?.validateDraft()
        }
        .store(in: &subscriptions)
    }

    func subscribeRecordPlayer() {
        guard let recordingPlayer else { return }
        recordPlayerSubscription = recordingPlayer.didPlayTillEnd
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.state = .hasRecording
            }
    }

    func unsubscribeRecordPlayer() {
        recordPlayerSubscription = nil
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
