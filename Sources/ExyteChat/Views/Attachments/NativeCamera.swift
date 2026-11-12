import AVFoundation
import CoreImage
import Observation
import Synchronization
import SwiftUI

enum NativeCameraMode: String, CaseIterable {
    case photo
    case video
}

@MainActor
@Observable
final class NativeCameraModel {
    @ObservationIgnored let session = AVCaptureSession()

    private(set) var videoDevice: AVCaptureDevice?
    private(set) var previewImage: CGImage?
    private(set) var isConfigured = false
    private(set) var mode: NativeCameraMode = .photo
    private(set) var isRecording = false
    var alertMessage: String?

    @ObservationIgnored private let captureService: NativeCameraCaptureService
    @ObservationIgnored private let previewImageStream: AsyncStream<CGImage>
    @ObservationIgnored private var previewImageTask: Task<Void, Never>?
    @ObservationIgnored
    private let onCapture: (DraftMedia) -> Void
    @ObservationIgnored
    private var acceptsCaptureResults = true
    @ObservationIgnored
    private var isActive = false

    init(onCapture: @escaping (DraftMedia) -> Void) {
        let (previewImageStream, previewImageContinuation) = AsyncStream.makeStream(
            of: CGImage.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.previewImageStream = previewImageStream
        self.onCapture = onCapture
        captureService = NativeCameraCaptureService(
            session: session,
            previewImageContinuation: previewImageContinuation
        )
    }

    func start() {
        isActive = true
        acceptsCaptureResults = true
        observePreviewImages()
        Task { [weak self] in
            guard await Self.requestAccess(for: .video) else {
                guard self?.isActive == true else { return }
                self?.alertMessage = "Allow camera access in Settings to capture a photo or video."
                return
            }
            guard self?.isActive == true else { return }

            self?.captureService.configure { [weak self] deviceReference, errorMessage in
                guard let self else { return }
                if let deviceReference {
                    self.videoDevice = deviceReference.device
                    self.isConfigured = true
                } else {
                    self.alertMessage = errorMessage ?? "The camera could not be started."
                }
            }
        }
    }

    func stop() {
        isActive = false
        acceptsCaptureResults = false
        previewImageTask?.cancel()
        previewImageTask = nil
        previewImage = nil
        captureService.stopSession()
    }

    private func observePreviewImages() {
        guard previewImageTask == nil else { return }
        let previewImageStream = previewImageStream
        previewImageTask = Task { @MainActor [weak self, previewImageStream] in
            for await image in previewImageStream {
                guard !Task.isCancelled, let self else { return }
                self.previewImage = image
            }
        }
    }

    func selectMode(_ newMode: NativeCameraMode) {
        guard newMode != mode else { return }

        Task { [weak self] in
            if newMode == .video {
                guard await Self.requestAccess(for: .audio) else {
                    guard self?.isActive == true else { return }
                    self?.alertMessage = "Allow microphone access in Settings to record videos with audio."
                    return
                }
            }
            guard self?.isActive == true else { return }

            self?.captureService.setMode(newMode) { [weak self] errorMessage in
                guard let self else { return }
                if let errorMessage {
                    self.alertMessage = errorMessage
                } else {
                    self.mode = newMode
                }
            }
        }
    }

    func capture() {
        guard isConfigured else { return }

        switch mode {
        case .photo:
            captureService.capturePhoto { [weak self] url, errorMessage in
                guard let self, self.acceptsCaptureResults else { return }
                if let url {
                    self.onCapture(DraftMedia(url: url, type: .image))
                } else {
                    self.alertMessage = errorMessage ?? "The photo could not be captured."
                }
            }
        case .video:
            if isRecording {
                isRecording = false
                captureService.stopRecording()
            } else {
                captureService.startRecording { [weak self] didStart, errorMessage in
                    guard let self else { return }
                    self.isRecording = didStart
                    if let errorMessage {
                        self.alertMessage = errorMessage
                    }
                } onFinish: { [weak self] url, errorMessage in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.isRecording = false
                        guard self.acceptsCaptureResults else { return }
                        if let url, self.acceptsCaptureResults {
                            guard let media = await NativeMediaImporter.makeDraftMedia(url: url, type: .video) else {
                                self.alertMessage = "A preview could not be created for the recorded video."
                                return
                            }
                            self.onCapture(media)
                        } else {
                            self.alertMessage = errorMessage ?? "The video could not be recorded."
                        }
                    }
                }
            }
        }
    }

    func updateCaptureRotationAngle(_ angle: CGFloat) {
        captureService.setCaptureRotationAngle(angle)
    }

    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

// SAFETY: `sessionExecutor` serializes every access to the capture graph and mutable service state.
// Sample-buffer processing is confined to `videoQueue`; preview images cross to the UI through AsyncStream.
// Follow-up: remove this conformance when AVFoundation delegate requirements are Sendable or when its
// Objective-C delegates can be isolated behind framework-supported async APIs.
private final class NativeCameraCaptureService: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session: AVCaptureSession
    private let sessionExecutor = CameraSessionExecutor()
    // AVCaptureVideoDataOutput requires a serial delegate queue for sample buffers.
    private let videoQueue = DispatchQueue(label: "com.exyte.chat.camera-preview")
    private let previewImageContinuation: AsyncStream<CGImage>.Continuation
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let imageContext = CIContext()
    private var audioInput: AVCaptureDeviceInput?
    private var captureAngle: CGFloat = 0
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var recordingCompletion: (@MainActor @Sendable (URL?, String?) -> Void)?
    private var stopSessionAfterRecording = false

    init(
        session: AVCaptureSession,
        previewImageContinuation: AsyncStream<CGImage>.Continuation
    ) {
        self.session = session
        self.previewImageContinuation = previewImageContinuation
        super.init()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
    }

    func configure(completion: @escaping @MainActor @Sendable (CameraDeviceReference?, String?) -> Void) {
        performOnSession { [weak self] in
            guard let self else { return }
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video) else {
                    throw NativeCameraError.cameraUnavailable
                }

                let input = try AVCaptureDeviceInput(device: camera)
                self.session.beginConfiguration()
                do {
                    if self.session.canSetSessionPreset(.photo) {
                        self.session.sessionPreset = .photo
                    }
                    guard self.session.canAddInput(input) else {
                        throw NativeCameraError.cannotAddCameraInput
                    }
                    guard self.session.canAddOutput(self.photoOutput) else {
                        throw NativeCameraError.cannotAddPhotoOutput
                    }
                    guard self.session.canAddOutput(self.videoDataOutput) else {
                        throw NativeCameraError.cannotAddVideoDataOutput
                    }

                    self.session.addInput(input)
                    self.session.addOutput(self.photoOutput)
                    self.session.addOutput(self.videoDataOutput)
                } catch {
                    self.session.commitConfiguration()
                    throw error
                }
                self.session.commitConfiguration()
                self.applyCaptureRotationAngle()
                self.session.startRunning()
                Task { @MainActor in completion(CameraDeviceReference(camera), nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(nil, message) }
            }
        }
    }

    func stopSession() {
        performOnSession { [weak self] in
            guard let self, self.session.isRunning else { return }
            if self.movieOutput.isRecording {
                self.stopSessionAfterRecording = true
                self.movieOutput.stopRecording()
            } else {
                self.session.stopRunning()
            }
        }
    }

    func setMode(_ mode: NativeCameraMode, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        performOnSession { [weak self] in
            guard let self else { return }
            do {
                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                switch mode {
                case .photo:
                    if self.session.outputs.contains(where: { $0 === self.movieOutput }) {
                        self.session.removeOutput(self.movieOutput)
                    }
                    if !self.session.outputs.contains(where: { $0 === self.photoOutput }) {
                        guard self.session.canAddOutput(self.photoOutput) else {
                            throw NativeCameraError.cannotAddPhotoOutput
                        }
                        self.session.addOutput(self.photoOutput)
                    }
                    if self.session.canSetSessionPreset(.photo) {
                        self.session.sessionPreset = .photo
                    }
                case .video:
                    if self.audioInput == nil {
                        guard let microphone = AVCaptureDevice.default(for: .audio) else {
                            throw NativeCameraError.microphoneUnavailable
                        }
                        let input = try AVCaptureDeviceInput(device: microphone)
                        guard self.session.canAddInput(input) else {
                            throw NativeCameraError.cannotAddMicrophoneInput
                        }
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                    if self.session.outputs.contains(where: { $0 === self.photoOutput }) {
                        self.session.removeOutput(self.photoOutput)
                    }
                    if !self.session.outputs.contains(where: { $0 === self.movieOutput }) {
                        guard self.session.canAddOutput(self.movieOutput) else {
                            throw NativeCameraError.cannotAddMovieOutput
                        }
                        self.session.addOutput(self.movieOutput)
                    }
                    if self.session.canSetSessionPreset(.high) {
                        self.session.sessionPreset = .high
                    }
                }

                self.applyCaptureRotationAngle()
                Task { @MainActor in completion(nil) }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in completion(message) }
            }
        }
    }

    func capturePhoto(completion: @escaping @MainActor @Sendable (URL?, String?) -> Void) {
        performOnSession { [weak self] in
            guard let self else { return }
            guard self.session.outputs.contains(where: { $0 === self.photoOutput }) else {
                Task { @MainActor in
                    completion(nil, NativeCameraError.photoCaptureUnavailable.localizedDescription)
                }
                return
            }

            self.applyCaptureRotationAngle()
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            let uniqueID = settings.uniqueID
            let delegate = PhotoCaptureDelegate(uniqueID: uniqueID, completion: completion) { [weak self] in
                guard let self else { return }
                self.performOnSession {
                    self.photoDelegates.removeValue(forKey: uniqueID)
                }
            }
            self.photoDelegates[uniqueID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func startRecording(
        onStart: @escaping @MainActor @Sendable (Bool, String?) -> Void,
        onFinish: @escaping @MainActor @Sendable (URL?, String?) -> Void
    ) {
        performOnSession { [weak self] in
            guard let self else { return }
            guard !self.movieOutput.isRecording,
                  self.session.outputs.contains(where: { $0 === self.movieOutput }) else {
                Task { @MainActor in
                    onStart(false, NativeCameraError.videoCaptureUnavailable.localizedDescription)
                }
                return
            }

            self.applyCaptureRotationAngle()
            let url = NativeMediaImporter.makeTemporaryFileURL(fileExtension: "mov")
            self.recordingCompletion = onFinish
            self.stopSessionAfterRecording = false
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            Task { @MainActor in onStart(true, nil) }
        }
    }

    func stopRecording() {
        performOnSession { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func setCaptureRotationAngle(_ angle: CGFloat) {
        performOnSession { [weak self] in
            guard let self else { return }
            self.captureAngle = angle
            self.applyCaptureRotationAngle()
        }
    }

    private func applyCaptureRotationAngle() {
        for output in [photoOutput, movieOutput, videoDataOutput] {
            guard let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(captureAngle) else { continue }
            connection.videoRotationAngle = captureAngle
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoDataOutput,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }

        previewImageContinuation.yield(cgImage)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let message = error?.localizedDescription
        performOnSession { [weak self] in
            guard let self else { return }
            let completion = self.recordingCompletion
            self.recordingCompletion = nil
            if let message {
                Task { @MainActor in completion?(nil, message) }
            } else {
                Task { @MainActor in completion?(outputFileURL, nil) }
            }
            self.stopSessionIfRequested()
        }
    }

    private func stopSessionIfRequested() {
        guard stopSessionAfterRecording else { return }
        stopSessionAfterRecording = false
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func performOnSession(_ operation: @escaping @Sendable () -> Void) {
        let executor = sessionExecutor
        Task {
            await executor.perform(operation)
        }
    }
}

private actor CameraSessionExecutor {
    func perform(_ operation: @Sendable () -> Void) {
        operation()
    }
}

// SAFETY: Capture inputs and callbacks are immutable; the one-shot completion gate is protected by Mutex.
// Follow-up: remove this conformance when AVFoundation's NSObject delegate protocol is Sendable.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let uniqueID: Int64
    private let completion: @MainActor @Sendable (URL?, String?) -> Void
    private let onFinish: @Sendable () -> Void
    private let completionGate = Mutex(false)

    init(
        uniqueID: Int64,
        completion: @escaping @MainActor @Sendable (URL?, String?) -> Void,
        onFinish: @escaping @Sendable () -> Void
    ) {
        self.uniqueID = uniqueID
        self.completion = completion
        self.onFinish = onFinish
    }

    func finish(url: URL?, errorMessage: String?) {
        let shouldComplete = completionGate.withLock { didComplete in
            guard !didComplete else { return false }
            didComplete = true
            return true
        }
        guard shouldComplete else { return }
        let completion = self.completion
        Task { @MainActor in completion(url, errorMessage) }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard photo.resolvedSettings.uniqueID == uniqueID else { return }
        guard error == nil, let data = photo.fileDataRepresentation() else {
            finish(url: nil, errorMessage: error?.localizedDescription ?? NativeCameraError.photoCaptureFailed.localizedDescription)
            return
        }

        do {
            let fileExtension = NativeMediaImporter.imageFileExtension(for: data)
            let url = try NativeMediaImporter.writeTemporaryFile(data, fileExtension: fileExtension)
            finish(url: url, errorMessage: nil)
        } catch {
            finish(url: nil, errorMessage: error.localizedDescription)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        guard resolvedSettings.uniqueID == uniqueID else { return }
        if let error {
            finish(url: nil, errorMessage: error.localizedDescription)
        }
        onFinish()
    }
}

// SAFETY: The wrapper is immutable and transfers the device handle once to MainActor for rotation observation;
// capture-session configuration stays isolated to CameraSessionExecutor. Replace with a Sendable device ID and
// a main-actor device lookup if AVFoundation exposes a safe lookup/conformance for this use case.
private struct CameraDeviceReference: @unchecked Sendable {
    let device: AVCaptureDevice

    init(_ device: AVCaptureDevice) {
        self.device = device
    }
}

private enum NativeCameraError: LocalizedError {
    case cameraUnavailable
    case cannotAddCameraInput
    case cannotAddMicrophoneInput
    case microphoneUnavailable
    case cannotAddPhotoOutput
    case cannotAddVideoDataOutput
    case cannotAddMovieOutput
    case photoCaptureUnavailable
    case videoCaptureUnavailable
    case photoCaptureFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "No camera is available on this device."
        case .cannotAddCameraInput: "The camera could not be connected."
        case .cannotAddMicrophoneInput: "The microphone could not be connected."
        case .microphoneUnavailable: "No microphone is available on this device."
        case .cannotAddPhotoOutput: "Photo capture is unavailable."
        case .cannotAddVideoDataOutput: "Camera preview is unavailable."
        case .cannotAddMovieOutput: "Video capture is unavailable."
        case .photoCaptureUnavailable: "Photo capture is not ready."
        case .videoCaptureUnavailable: "Video capture is not ready."
        case .photoCaptureFailed: "The photo could not be captured."
        }
    }
}

struct NativeCameraView: View {
    let onCancel: () -> Void

    @State private var model: NativeCameraModel
    @State private var rotationObserver = CameraRotationObserver()

    init(onCapture: @escaping (DraftMedia) -> Void, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        _model = State(initialValue: NativeCameraModel(onCapture: onCapture))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(image: model.previewImage)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel("Close camera")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                HStack(spacing: 28) {
                    modeButton(.photo)
                    modeButton(.video)
                }
                .padding(.bottom, 20)

                Button(action: model.capture) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 74, height: 74)
                        if model.isRecording {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(model.mode == .video ? .red : .white)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .disabled(!model.isConfigured)
                .opacity(model.isConfigured ? 1 : 0.5)
                .accessibilityLabel(model.isRecording ? "Stop recording" : model.mode == .video ? "Start recording" : "Take photo")
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
        .onChange(of: model.videoDevice?.uniqueID) { _, _ in
            guard let videoDevice = model.videoDevice else { return }
            rotationObserver.update(device: videoDevice, model: model)
        }
        .alert("Camera", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private func modeButton(_ mode: NativeCameraMode) -> some View {
        Button {
            model.selectMode(mode)
        } label: {
            Text(mode.rawValue.uppercased())
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
                .foregroundStyle(model.mode == mode ? .yellow : .white)
        }
        .disabled(!model.isConfigured || model.isRecording)
    }
}

private struct CameraPreview: View {
    let image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(image, scale: 1, orientation: .up, label: Text("Camera preview"))
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class CameraRotationObserver {
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var captureAngleObservation: NSKeyValueObservation?
    private var observedDeviceID: String?

    func update(device: AVCaptureDevice, model: NativeCameraModel) {
        guard observedDeviceID != device.uniqueID else { return }
        observedDeviceID = device.uniqueID
        captureAngleObservation?.invalidate()

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        model.updateCaptureRotationAngle(coordinator.videoRotationAngleForHorizonLevelCapture)

        captureAngleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { _, change in
            guard let angle = change.newValue else { return }
            Task { @MainActor in
                model.updateCaptureRotationAngle(angle)
            }
        }
    }
}
