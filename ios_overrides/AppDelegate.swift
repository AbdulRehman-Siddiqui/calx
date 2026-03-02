import UIKit
import Flutter
import FlutterPluginRegistrant
import AVFoundation

// MARK: - Camera Engine (AVFoundation; no background persistence)

final class CameraEngine {
    static let shared = CameraEngine()

    private let queue = DispatchQueue(label: "calx.camera.queue")

    private let session = AVCaptureSession()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let movieOutput = AVCaptureMovieFileOutput()

    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var currentZoom: CGFloat = 1.0
    private var currentFps: Int32 = 30

    private init() {}

    func attachPreview(to view: UIView) {
        queue.async {
            if self.previewLayer == nil {
                let layer = AVCaptureVideoPreviewLayer(session: self.session)
                layer.videoGravity = .resizeAspectFill
                self.previewLayer = layer
            }
            DispatchQueue.main.async {
                guard let layer = self.previewLayer else { return }
                layer.frame = view.bounds
                if layer.superlayer == nil {
                    view.layer.insertSublayer(layer, at: 0)
                }
            }
        }
    }

    func updatePreviewFrame(_ frame: CGRect) {
        DispatchQueue.main.async { self.previewLayer?.frame = frame }
    }

    func initializeIfNeeded(completion: @escaping (Bool, String?) -> Void) {
        queue.async {
            if self.session.inputs.count > 0 {
                self.startSession()
                completion(true, nil)
                return
            }

            let group = DispatchGroup()
            var camGranted = false
            var micGranted = false

            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { ok in
                camGranted = ok
                group.leave()
            }

            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                micGranted = ok
                group.leave()
            }

            group.notify(queue: self.queue) {
                guard camGranted else { completion(false, "Camera permission denied"); return }
                guard micGranted else { completion(false, "Microphone permission denied"); return }

                do {
                    try self.configureSession()
                    self.startSession()
                    completion(true, nil)
                } catch {
                    completion(false, "Configure session failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw NSError(domain: "calx", code: -1, userInfo: [NSLocalizedDescriptionKey: "Back camera not found"])
        }

        let vIn = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(vIn) { session.addInput(vIn) }
        self.videoInput = vIn

        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            let aIn = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(aIn) { session.addInput(aIn) }
            self.audioInput = aIn
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        session.commitConfiguration()

        setFrameRateInternal(currentFps)
        setZoomInternal(currentZoom)
    }

    func startSession() {
        queue.async {
            if !self.session.isRunning {
                self.session.startRunning()
                print("[calx] session started")
            }
        }
    }

    func stopSession() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
                print("[calx] session stopped")
            }
        }
    }

    // MARK: Recording

    func startRecording(completion: @escaping (Bool, String?) -> Void) {
        queue.async {
            guard !self.movieOutput.isRecording else {
                completion(false, "Already recording")
                return
            }

            if !self.session.isRunning { self.session.startRunning() }

            guard let url = self.makeRecordingURL() else {
                completion(false, "Documents directory not available")
                return
            }

            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
            } catch {
                print("[calx] Audio session warning: \(error)")
            }

            RecordingDelegate.shared.onFinish = { outURL, err in
                if let err = err { completion(false, err) }
                else { completion(true, outURL?.path ?? "Saved") }
            }

            self.movieOutput.startRecording(to: url, recordingDelegate: RecordingDelegate.shared)
            print("[calx] startRecording -> \(url.lastPathComponent)")
        }
    }

    func stopRecording() {
        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
                print("[calx] stopRecording")
            }
        }
    }

    func isRecording() -> Bool { movieOutput.isRecording }

    // MARK: Zoom

    func setZoom(_ zoom: CGFloat) {
        queue.async { self.setZoomInternal(zoom) }
    }

    private func setZoomInternal(_ zoom: CGFloat) {
        guard let device = videoInput?.device else { return }
        let minZoom: CGFloat = (device.minAvailableVideoZoomFactor < 1.0) ? max(0.5, device.minAvailableVideoZoomFactor) : 1.0
        let maxZoom = device.activeFormat.videoMaxZoomFactor
        let z = max(minZoom, min(zoom, maxZoom))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = z
            device.unlockForConfiguration()
            currentZoom = z
            print("[calx] zoom set -> \(z)")
        } catch {
            print("[calx] zoom lock failed: \(error)")
        }
    }

    // MARK: FPS

    func setFrameRate(_ fps: Int32) {
        queue.async { self.setFrameRateInternal(fps) }
    }

    private func setFrameRateInternal(_ fps: Int32) {
        guard let device = videoInput?.device else { return }

        var bestFormat: AVCaptureDevice.Format?
        var bestDiff: Int32 = Int32.max
        var bestRange: AVFrameRateRange?

        for format in device.formats {
            for range in format.videoSupportedFrameRateRanges {
                let minF = Int32(range.minFrameRate.rounded())
                let maxF = Int32(range.maxFrameRate.rounded())
                let supported = (fps >= minF && fps <= maxF)

                let diff: Int32
                if supported { diff = 0 }
                else if fps < minF { diff = minF - fps }
                else { diff = fps - maxF }

                if diff < bestDiff {
                    bestDiff = diff
                    bestFormat = format
                    bestRange = range
                }
            }
        }

        guard let chosenFormat = bestFormat else {
            print("[calx] no format found for fps \(fps)")
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = chosenFormat

            if let r = bestRange {
                let minF = Double(r.minFrameRate)
                let maxF = Double(r.maxFrameRate)
                let desired = Double(fps)
                let chosen = max(minF, min(desired, maxF))
                let duration = CMTime(value: 1, timescale: CMTimeScale(chosen.rounded()))
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                currentFps = Int32(chosen.rounded())
                print("[calx] fps set -> requested \(fps), chosen \(currentFps)")
            }

            device.unlockForConfiguration()
        } catch {
            print("[calx] fps lock failed: \(error)")
        }
    }

    private func makeRecordingURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = df.string(from: Date())
        return docs.appendingPathComponent("recording_\(stamp).mp4")
    }
}

// MARK: Recording Delegate

final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    static let shared = RecordingDelegate()
    var onFinish: ((URL?, String?) -> Void)?

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        if let error = error {
            print("[calx] recording finished with error: \(error)")
            onFinish?(nil, error.localizedDescription)
        } else {
            print("[calx] recording finished OK: \(outputFileURL.lastPathComponent)")
            onFinish?(outputFileURL, nil)
        }
        onFinish = nil
    }
}

// MARK: Platform View (preview)

final class CalxCameraPreviewView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        CameraEngine.shared.attachPreview(to: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CameraEngine.shared.updatePreviewFrame(bounds)
    }
}

final class CalxCameraPreviewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        CalxCameraPreviewPlatformView(frame: frame)
    }
}

final class CalxCameraPreviewPlatformView: NSObject, FlutterPlatformView {
    private let previewView: CalxCameraPreviewView

    init(frame: CGRect) {
        self.previewView = CalxCameraPreviewView(frame: frame)
        super.init()

        CameraEngine.shared.initializeIfNeeded { ok, msg in
            print("[calx] initIfNeeded -> ok=\(ok) msg=\(msg ?? "nil")")
        }
    }

    func view() -> UIView { previewView }
}

// MARK: Privacy overlay (black window)

final class PrivacyOverlay {
    static let shared = PrivacyOverlay()
    private var overlayWindow: UIWindow?

    private init() {}

    func show() {
        DispatchQueue.main.async {
            guard self.overlayWindow == nil else { return }
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

            let w = UIWindow(windowScene: windowScene)
            w.windowLevel = .alert + 1
            w.backgroundColor = .black
            w.rootViewController = UIViewController()
            w.rootViewController?.view.backgroundColor = .black
            w.isHidden = false
            self.overlayWindow = w

            print("[calx] privacy overlay SHOW")
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.overlayWindow?.isHidden = true
            self.overlayWindow = nil
            print("[calx] privacy overlay HIDE")
        }
    }
}

// MARK: Flutter VC (hide status bar)

final class CalxFlutterViewController: FlutterViewController {
    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
}

// MARK: AppDelegate

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Build a FlutterEngine manually so we can use a custom root VC.
        let flutterEngine = FlutterEngine(name: "calx_engine")
        flutterEngine.run()

        // Register plugins (important!)
        GeneratedPluginRegistrant.register(with: flutterEngine)

        let vc = CalxFlutterViewController(engine: flutterEngine, nibName: nil, bundle: nil)
        self.window = UIWindow(frame: UIScreen.main.bounds)
        self.window?.rootViewController = vc
        self.window?.makeKeyAndVisible()

        // Platform view registration
        guard let registrar = flutterEngine.registrar(forPlugin: "calx_camera_preview") else {
            fatalError("[calx] Failed to get plugin registrar")
        }

        registrar.register(
            CalxCameraPreviewFactory(messenger: registrar.messenger()),
            withId: "calx/camera_preview"
        )

        // Method channel
        methodChannel = FlutterMethodChannel(
            name: "calx/camera",
            binaryMessenger: registrar.messenger()
        )

        methodChannel?.setMethodCallHandler { call, result in
            switch call.method {
            case "init":
                CameraEngine.shared.initializeIfNeeded { ok, msg in
                    if ok { result(true) }
                    else { result(FlutterError(code: "INIT_FAIL", message: msg, details: nil)) }
                }

            case "startRecording":
                CameraEngine.shared.startRecording { ok, msg in
                    if ok { result(msg ?? "OK") }
                    else { result(FlutterError(code: "REC_START_FAIL", message: msg, details: nil)) }
                }

            case "stopRecording":
                CameraEngine.shared.stopRecording()
                result(true)

            case "setZoom":
                if let args = call.arguments as? [String: Any],
                   let z = args["zoom"] as? Double {
                    CameraEngine.shared.setZoom(CGFloat(z))
                    result(true)
                } else {
                    result(FlutterError(code: "BAD_ARGS", message: "Missing zoom", details: nil))
                }

            case "setFps":
                if let args = call.arguments as? [String: Any],
                   let fps = args["fps"] as? Int {
                    CameraEngine.shared.setFrameRate(Int32(fps))
                    result(true)
                } else {
                    result(FlutterError(code: "BAD_ARGS", message: "Missing fps", details: nil))
                }

            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Privacy overlay + stop in background (no persistence)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    @objc private func onWillResignActive() {
        PrivacyOverlay.shared.show()
    }

    @objc private func onDidBecomeActive() {
        PrivacyOverlay.shared.hide()
        CameraEngine.shared.startSession()
    }

    @objc private func onDidEnterBackground() {
        if CameraEngine.shared.isRecording() {
            CameraEngine.shared.stopRecording()
        }
        CameraEngine.shared.stopSession()
    }
}
