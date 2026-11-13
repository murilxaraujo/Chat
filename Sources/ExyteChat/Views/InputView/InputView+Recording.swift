//
//  InputView+Recording.swift
//  Chat
//

import SwiftUI

private let tapDelay: Double = 0.2
private let stopRecordButtonOffset: CGFloat = 24

private enum RecordingActionButton: Equatable {
    case send
    case record
    case stop

    var symbol: String {
        switch self {
        case .send: "paperplane.fill"
        case .record: "mic.fill"
        case .stop: "stop.fill"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .send: "Send"
        case .record: "Record audio"
        case .stop: "Stop recording"
        }
    }
}

extension InputView {

    var recordingActionButton: some View {
        ZStack {
            if [.isRecordingTap, .isRecordingHold].contains(state) {
                RecordIndicator()
                    .viewSize(80)
                    .foregroundStyle(.tint)
            }

            primaryActionButton
                .compositingGroup()
                .overlay(alignment: .top) {
                    if !shouldUseTapToToggleRecording, state == .isRecordingTap {
                        stopRecordButton
                            .sizeGetter($stopRecordButtonSize)
                            .offset(y: -stopRecordButtonSize.height - stopRecordButtonOffset)
                    } else if !shouldUseTapToToggleRecording, state == .isRecordingHold {
                        lockRecordButton
                            .sizeGetter($lockRecordButtonSize)
                            .offset(y: -lockRecordButtonSize.height - stopRecordButtonOffset)
                    }
                }
        }
        .frame(width: 48, height: 48)
    }

    private var currentRecordingAction: RecordingActionButton {
        if shouldUseTapToToggleRecording, state == .isRecordingTap {
            return .stop
        }
        if state.canSend || !isAudioAvailable() {
            return .send
        }
        return .record
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        let button = actionButton(for: currentRecordingAction)

        if currentRecordingAction == .record, !shouldUseTapToToggleRecording {
            button
                .highPriorityGesture(dragGesture())
                .accessibilityAction(.default) {
                    onAction(.recordAudioTap)
                }
                .frameGetter($recordButtonFrame)
        } else {
            button
                .frameGetter($recordButtonFrame)
        }
    }

    private func actionButton(for action: RecordingActionButton) -> some View {
        Button {
            switch action {
            case .send:
                onAction(.send)
            case .record:
                if shouldUseTapToToggleRecording {
                    onAction(.recordAudioTap)
                }
            case .stop:
                onAction(.stopRecordAudio)
            }
        } label: {
            Image(systemName: action.symbol)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(Text(action.accessibilityLabel))
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .frame(width: 48, height: 48)
        .disabled(action == .send && !state.canSend)
    }

    var deleteRecordButton: some View {
        Button(role: .destructive) {
            onAction(.deleteRecord)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Delete recording")
        .frameGetter($deleteRecordFrame)
    }

    var stopRecordButton: some View {
        actionButton(for: .stop)
            .accessibilityLabel("Stop recording")
    }

    var lockRecordButton: some View {
        Button {
            onAction(.recordAudioLock)
        } label: {
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                Image(systemName: "paperplane.fill")
            }
            .frame(width: 28)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            )
        }
        .frameGetter($lockRecordFrame)
    }

    var swipeToCancel: some View {
        HStack {
            Spacer()
            Button {
                onAction(.deleteRecord)
            } label: {
                HStack {
                    Image(systemName: "xmark")
                        .renderingMode(.template)
                        .foregroundStyle(Color.primary)
                    Text(localization.cancelButtonText)
                        .font(.footnote)
                        .foregroundColor(Color.primary)
                }
            }
            Spacer()
        }
    }

    var recordingInProgress: some View {
        HStack {
            Spacer()
            Text(localization.recordingText)
                .font(.footnote)
                .foregroundColor(Color.primary)
            Spacer()
        }
    }

    var recordDurationInProcess: some View {
        HStack {
            Circle()
                .foregroundColor(Color.red)
                .viewSize(6)
            recordDuration
        }
    }

    var recordDuration: some View {
        Text(DateFormatter.timeString(Int(viewModel.attachments.recording?.duration ?? 0)))
            .foregroundColor(Color.primary)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var recordDurationLeft: some View {
        Text(DateFormatter.timeString(Int(recordingPlayer.secondsLeft)))
            .foregroundColor(Color.primary)
            .opacity(0.6)
            .font(.caption2)
            .monospacedDigit()
            .padding(.trailing, 12)
    }

    var playRecordButton: some View {
        Button {
            onAction(.playRecord)
        } label: {
            Image(systemName: "play.fill")
        }
    }

    var pauseRecordButton: some View {
        Button {
            onAction(.pauseRecord)
        } label: {
            Image(systemName: "pause.fill")
        }
    }

    @ViewBuilder
    var recordWaveform: some View {
        if let recording = viewModel.attachments.recording {
            HStack(spacing: 8) {
                Group {
                    if state == .hasRecording || state == .pausedRecording {
                        playRecordButton
                    } else if state == .playingRecording {
                        pauseRecordButton
                    }
                }
                .frame(width: 20)

                RecordWaveformPlaying(
                    samples: recording.waveformSamples,
                    progress: recordingPlayer.progress,
                    color: Color.primary,
                    addExtraDots: true
                ) { progress in
                    Task {
                        await recordingPlayer.seek(with: recording, to: progress)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
            .onChanged { [state] value in
                if dragStart == nil {
                    dragStart = Date()
                    cancelGesture = false
                    tapDelayTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .seconds(tapDelay))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled,
                              state != .isRecordingTap,
                              state != .waitingForRecordingPermission else { return }
                        onAction(.recordAudioHold)
                    }
                }

                if value.location.y < lockRecordFrame.minY,
                   value.location.x > recordButtonFrame.minX {
                    cancelGesture = true
                    onAction(.recordAudioLock)
                }

                if value.location.x < chatSize.width / 2,
                   value.location.y > recordButtonFrame.minY {
                    cancelGesture = true
                    onAction(.deleteRecord)
                }
            }
            .onEnded { value in
                tapDelayTask?.cancel()
                tapDelayTask = nil
                if !cancelGesture {
                    if recordButtonFrame.contains(value.location) {
                        if let dragStart = dragStart, Date().timeIntervalSince(dragStart) < tapDelay {
                            onAction(.recordAudioTap)
                        } else if state != .waitingForRecordingPermission {
                            onAction(.send)
                        }
                    } else if lockRecordFrame.contains(value.location) {
                        onAction(.recordAudioLock)
                    } else if deleteRecordFrame.contains(value.location) {
                        onAction(.deleteRecord)
                    } else {
                        onAction(.send)
                    }
                }
                dragStart = nil
            }
    }
}
