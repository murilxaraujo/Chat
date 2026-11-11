@preconcurrency import AVFoundation
import SwiftUI
import UIKit

enum NativeCameraMode: String, CaseIterable {
    case photo
    case video
}

@MainActor
final class NativeCameraModel: ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var videoDevice: AVCaptureDevice?
    @Published private(set) var isConfigured = false
    @Published private(set) var mode: NativeCameraMode = .photo
    @Published private(set) var isRecording = false
    @Published var alertMessage: String?

    private let captureService: NativeCameraCaptureService
    private let onCapture: (DraftMedia) -> Void
    private var acceptsCaptureResults = true
    private var isActive = false

    init(onCapture: @escaping (DraftMedia) -> Void) {
        self.onCapture = onCapture
        captureService = NativeCameraCaptureService(session: session)
    }

    func start() {
        isActive = true
        acceptsCaptureResults = true
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
        captureService.stopSession()
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

private final class NativeCameraCaptureService: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session: AVCaptureSession
    private let sessionQueue = DispatchQueue(label: "com.exyte.chat.camera-session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var audioInput: AVCaptureDeviceInput?
    private var captureAngle: CGFloat = 0
    private var photoDelegates: [Int64: PhotoCaptureDelegate] = [:]
    private var recordingCompletion: (@MainActor @Sendable (URL?, String?) -> Void)?
    private var stopSessionAfterRecording = false

    init(session: AVCaptureSession) {
        self.session = session
    }

    func configure(completion: @escaping @MainActor @Sendable (CameraDeviceReference?, String?) -> Void) {
        sessionQueue.async { [weak self] in
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

                    self.session.addInput(input)
                    self.session.addOutput(self.photoOutput)
                } catch {
                    self.session.commitConfiguration()
                    throw error
                }
                self.session.commitConfiguration()
                self.applyCaptureRotationAngle()
                self.session.startRunning()
                DispatchQueue.main.async { completion(CameraDeviceReference(camera), nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error.localizedDescription) }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
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
        sessionQueue.async { [weak self] in
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
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error.localizedDescription) }
            }
        }
    }

    func capturePhoto(completion: @escaping @MainActor @Sendable (URL?, String?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.outputs.contains(where: { $0 === self.photoOutput }) else {
                DispatchQueue.main.async { completion(nil, NativeCameraError.photoCaptureUnavailable.localizedDescription) }
                return
            }

            self.applyCaptureRotationAngle()
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            let delegate = PhotoCaptureDelegate(uniqueID: settings.uniqueID, completion: completion)
            self.photoDelegates[settings.uniqueID] = delegate
            delegate.onFinish = { [weak self] in
                guard let self else { return }
                self.sessionQueue.async {
                    self.photoDelegates.removeValue(forKey: settings.uniqueID)
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func startRecording(
        onStart: @escaping @MainActor @Sendable (Bool, String?) -> Void,
        onFinish: @escaping @MainActor @Sendable (URL?, String?) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.movieOutput.isRecording,
                  self.session.outputs.contains(where: { $0 === self.movieOutput }) else {
                DispatchQueue.main.async { onStart(false, NativeCameraError.videoCaptureUnavailable.localizedDescription) }
                return
            }

            self.applyCaptureRotationAngle()
            let url = NativeMediaImporter.makeTemporaryFileURL(fileExtension: "mov")
            self.recordingCompletion = onFinish
            self.stopSessionAfterRecording = false
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async { onStart(true, nil) }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func setCaptureRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureAngle = angle
            self.applyCaptureRotationAngle()
        }
    }

    private func applyCaptureRotationAngle() {
        for output in [photoOutput, movieOutput] {
            guard let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(captureAngle) else { continue }
            connection.videoRotationAngle = captureAngle
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let message = error?.localizedDescription
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let completion = self.recordingCompletion
            self.recordingCompletion = nil
            if let message {
                DispatchQueue.main.async {
                    completion?(nil, message)
                }
            } else {
                DispatchQueue.main.async {
                    completion?(outputFileURL, nil)
                }
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
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let uniqueID: Int64
    private let completion: @MainActor @Sendable (URL?, String?) -> Void
    var onFinish: (() -> Void)?
    private var didComplete = false

    init(uniqueID: Int64, completion: @escaping @MainActor @Sendable (URL?, String?) -> Void) {
        self.uniqueID = uniqueID
        self.completion = completion
    }

    func finish(url: URL?, errorMessage: String?) {
        guard !didComplete else { return }
        didComplete = true
        DispatchQueue.main.async { self.completion(url, errorMessage) }
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
        onFinish?()
    }
}

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
        case .cannotAddMovieOutput: "Video capture is unavailable."
        case .photoCaptureUnavailable: "Photo capture is not ready."
        case .videoCaptureUnavailable: "Video capture is not ready."
        case .photoCaptureFailed: "The photo could not be captured."
        }
    }
}

struct NativeCameraView: View {
    let onCancel: () -> Void

    @StateObject private var model: NativeCameraModel

    init(onCapture: @escaping (DraftMedia) -> Void, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        _model = StateObject(wrappedValue: NativeCameraModel(onCapture: onCapture))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.session, videoDevice: model.videoDevice, model: model)
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

@MainActor
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let videoDevice: AVCaptureDevice?
    let model: NativeCameraModel

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ view: CameraPreviewUIView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
        if let videoDevice {
            context.coordinator.rotationObserver.update(device: videoDevice, previewLayer: view.previewLayer, model: model)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let rotationObserver = CameraRotationObserver()
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private final class WeakCameraPreviewLayer: @unchecked Sendable {
    weak var value: AVCaptureVideoPreviewLayer?

    init(_ value: AVCaptureVideoPreviewLayer) {
        self.value = value
    }
}

@MainActor
private final class CameraRotationObserver {
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewAngleObservation: NSKeyValueObservation?
    private var captureAngleObservation: NSKeyValueObservation?
    private var observedDeviceID: String?

    func update(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer, model: NativeCameraModel) {
        guard observedDeviceID != device.uniqueID else { return }
        observedDeviceID = device.uniqueID
        previewAngleObservation?.invalidate()
        captureAngleObservation?.invalidate()

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        Self.applyPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview, to: previewLayer)
        model.updateCaptureRotationAngle(coordinator.videoRotationAngleForHorizonLevelCapture)

        let previewLayerReference = WeakCameraPreviewLayer(previewLayer)
        previewAngleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async {
                guard let previewLayer = previewLayerReference.value else { return }
                CameraRotationObserver.applyPreviewAngle(angle, to: previewLayer)
            }
        }

        captureAngleObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { _, change in
            guard let angle = change.newValue else { return }
            DispatchQueue.main.async {
                model.updateCaptureRotationAngle(angle)
            }
        }
    }

    private static func applyPreviewAngle(_ angle: CGFloat, to previewLayer: AVCaptureVideoPreviewLayer) {
        guard let connection = previewLayer.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
