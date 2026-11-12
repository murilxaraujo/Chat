//
//  InputView+Recording.swift
//  Chat
//

import SwiftUI

private let tapDelay: Double = 0.2
private let stopRecordButtonOffset: CGFloat = 24

extension InputView {

    var holdToRecordButton: some View {
        ZStack {
            if [.isRecordingTap, .isRecordingHold].contains(state) {
                RecordIndicator()
                    .viewSize(80)
                    .foregroundStyle(.tint)
            }

            Group {
                if state.canSend || !isAudioAvailable() {
                    sendButton
                        .disabled(!state.canSend)
                } else {
                    recordButton
                        .highPriorityGesture(dragGesture())
                }
            }
            .compositingGroup()
            .overlay(alignment: .top) {
                if state == .isRecordingTap {
                    stopRecordButton
                        .sizeGetter($stopRecordButtonSize)
                        .offset(y: -stopRecordButtonSize.height - stopRecordButtonOffset)
                } else if state == .isRecordingHold {
                    lockRecordButton
                        .sizeGetter($lockRecordButtonSize)
                        .offset(y: -lockRecordButtonSize.height - stopRecordButtonOffset)
                }
            }
        }
        .viewSize(48)
    }

    var tapToToggleButton: some View {
        ZStack {
            if state == .isRecordingTap {
                RecordIndicator()
                    .viewSize(80)
                    .foregroundStyle(.tint)
            }

            if state == .isRecordingTap {
                stopRecordButton
            } else if state.canSend || !isAudioAvailable() {
                sendButton
                    .disabled(!state.canSend)
            } else {
                recordButton
                    .onTapGesture {
                        onAction(.recordAudioTap)
                    }
            }
        }
        .viewSize(48)
    }

    var recordButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 20, weight: .medium))
            .frame(width: 48, height: 48)
            .foregroundStyle(.white)
            .background(.tint, in: Circle())
            .frameGetter($recordButtonFrame)
    }

    var deleteRecordButton: some View {
        Button {
            onAction(.deleteRecord)
        } label: {
            Image(systemName: "trash")
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 8))
        }
        .frameGetter($deleteRecordFrame)
    }

    var stopRecordButton: some View {
        Button {
            onAction(.stopRecordAudio)
        } label: {
            Image(systemName: "stop.fill")
                .viewSize(28)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.4), radius: 1)
                )
        }
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
                    tapDelayTimer = Timer.scheduledTimer(withTimeInterval: tapDelay, repeats: false) { _ in
                        if state != .isRecordingTap, state != .waitingForRecordingPermission {
                            DispatchQueue.main.async {
                                self.onAction(.recordAudioHold)
                            }
                        }
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
                if !cancelGesture {
                    tapDelayTimer = nil
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
