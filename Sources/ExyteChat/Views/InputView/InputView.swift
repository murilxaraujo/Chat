//
//  InputView.swift
//  Chat
//
//  Created by Alex.M on 25.05.2022.
//

import SwiftUI

struct InputView: View {

    @Environment(\.chatSize) var chatSize

    @EnvironmentObject var keyboardState: KeyboardState

    @Bindable var viewModel: InputViewModel
    @State var recordingPlayer = RecordingPlayer()

    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var recorderSettings: RecorderSettings = RecorderSettings()
    var audioRecordingMode: AudioRecordingMode = .holdToRecord
    var localization: ChatLocalization

    @State var stopRecordButtonSize: CGSize = .zero
    @State var lockRecordButtonSize: CGSize = .zero

    @State var recordButtonFrame: CGRect = .zero
    @State var lockRecordFrame: CGRect = .zero
    @State var deleteRecordFrame: CGRect = .zero

    @State var dragStart: Date?
    @State var tapDelayTask: Task<Void, Never>?
    @State var cancelGesture = false

    var onAction: (InputViewAction) -> Void {
        viewModel.inputViewAction()
    }

    var state: InputViewState {
        viewModel.state
    }

    var body: some View {
        ChatInputBar(
            accessory: {
                viewOnTop
                    .padding(.top, 6)
                    .transition(.move(edge: .bottom))
            },
            leading: { leftView },
            content: { middleView },
            trailing: { rightView },
            action: { rightOutsideButton }
        )
        .onAppear {
            viewModel.recordingPlayer = recordingPlayer
        }
        .onDisappear {
            viewModel.stopRecordingWhenViewDisappears()
        }
        .task {
            await viewModel.setRecorderSettings(recorderSettings: recorderSettings)
        }
        .task {
            for await _ in recordingPlayer.playbackEnded {
                guard !Task.isCancelled else { return }
                viewModel.recordingPlaybackDidFinish()
            }
        }
        .onDrag(towards: .bottom, ofAmount: 100...) {
            keyboardState.dismissKeyboard()
        }
    }

    @ViewBuilder
    var leftView: some View {
        if [.isRecordingTap, .isRecordingHold, .hasRecording, .playingRecording, .pausedRecording].contains(state) {
            leadingActionStyle(deleteRecordButton)
        } else {
            switch style {
            case .message:
                leadingActionStyle(leftButton)
            case .signature:
                leadingActionStyle(addButton)
            }
        }
    }

    func leadingActionStyle<Content: View>(_ content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(width: 48, height: 48)
    }

    @ViewBuilder
    var middleView: some View {
        Group {
            switch state {
            case .hasRecording, .playingRecording, .pausedRecording:
                recordWaveform
            case .isRecordingHold:
                swipeToCancel
            case .isRecordingTap:
                recordingInProgress
            default:
                TextInputView(
                    text: $viewModel.text,
                    inputFieldId: inputFieldId,
                    style: style,
                    availableInputs: availableInputs,
                    localization: localization
                )
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var rightView: some View {
        Group {
            switch state {
            case .hasTextOrMedia:
                if case .message = style, !viewModel.text.isEmpty {
                    clearTextButton
                }
            case .isRecordingHold, .isRecordingTap:
                recordDurationInProcess
            case .hasRecording:
                recordDuration
            case .playingRecording, .pausedRecording:
                recordDurationLeft
            default:
                EmptyView()
            }
        }
        .frame(minHeight: 48)
    }

    @ViewBuilder
    var rightOutsideButton: some View {
        if viewModel.isImportingMedia {
            ProgressView()
                .tint(.white)
                .viewSize(48)
                .background(.tint, in: Circle())
        } else if state == .editing {
            editingButtons
                .frame(height: 48)
        } else {
            recordingActionButton
        }
    }

    var shouldUseTapToToggleRecording: Bool {
        #if os(macOS)
        true
        #else
        audioRecordingMode == .tapToToggle
        #endif
    }

    @ViewBuilder
    var editingButtons: some View {
        HStack {
            Button(role: .cancel) {
                onAction(.cancelEdit)
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.bold)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Cancel editing")

            Button {
                onAction(.saveEdit)
            } label: {
                Image(systemName: "checkmark")
                    .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel("Save edited message")
        }
    }

    var addButton: some View {
        Button {
            onAction(.add)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 48)
        }
    }

    var clearTextButton: some View {
        Button {
            viewModel.text = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 12))
        }
    }

    func isAudioAvailable() -> Bool {
        availableInputs.contains(AvailableInputType.audio)
    }

    func isMediaAvailable() -> Bool {
        availableInputs.contains(AvailableInputType.media)
    }

    func isDocumentAvailable() -> Bool {
        availableInputs.contains(AvailableInputType.document)
    }

    func isLocationAvailable() -> Bool {
        availableInputs.contains(AvailableInputType.staticLocation) || availableInputs.contains(AvailableInputType.liveLocation)
    }
}

#Preview("Message composer") {
    InputViewPreviewHost()
}

@MainActor
private struct InputViewPreviewHost: View {
    @State private var viewModel = InputViewModel()
    @StateObject private var keyboardState = KeyboardState()
    @State private var globalFocusState = GlobalFocusState()
    @State private var lastSentMessage: String?

    private let inputFieldID = UUID()
    private let previewSize = CGSize(width: 390, height: 160)

    var body: some View {
        VStack {
            if let lastSentMessage {
                Text("Last sent: \(lastSentMessage)")
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            Spacer(minLength: 0)
            InputView(
                viewModel: viewModel,
                inputFieldId: inputFieldID,
                style: .message,
                availableInputs: [.text, .media, .document, .staticLocation, .liveLocation, .audio],
                localization: .defaultLocalization
            )
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .background(Color.secondary.opacity(0.08))
        .environment(\.chatSize, previewSize)
        .environmentObject(keyboardState)
        .environment(globalFocusState)
        .onAppear {
            viewModel.didSendMessage = { draft in
                lastSentMessage = draft.text.isEmpty ? "Attachment sent" : draft.text
            }
        }
    }
}
