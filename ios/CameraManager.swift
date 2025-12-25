//
//  CameraManager.swift
//  react-native-scanner
//
//  Manages AVFoundation camera operations
//

import AVFoundation
import UIKit

/// Manages camera session, input, and output
class CameraManager: NSObject, CameraControlProtocol {
    
    // MARK: - Public Properties
    
    /// Delegate for camera events
    weak var delegate: CameraManagerDelegate?
    
    /// The preview layer for displaying camera feed
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    
    // MARK: - Private Properties
    
    /// Main capture session
    private let captureSession: AVCaptureSession
    
    /// Background queue for camera operations
    private let sessionQueue: DispatchQueue
    
    /// Video data output for frame capture
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    /// Current camera device
    private var currentDevice: AVCaptureDevice?
    
    /// Current camera input
    private var currentInput: AVCaptureDeviceInput?
    
    /// Whether the session is running
    private var isSessionRunning: Bool

    /// Whether the session has been configured at least once
    private var isSessionConfigured: Bool = false

    // Desired settings (can be set before camera is configured/running)
    private var desiredTorchEnabled: Bool = false
    private var desiredTorchLevel: Float = 1.0
    private var desiredZoomLevel: CGFloat = 1.0
    
    // MARK: - Initialization
    
    override init() {
        self.captureSession = AVCaptureSession()
        self.sessionQueue = DispatchQueue(label: "com.scanner.camera.session")
        self.isSessionRunning = false
        
        super.init()
    }
    
    // MARK: - CameraControlProtocol Methods
    
    /// Start the camera session
    func startCamera() {
        checkCameraPermission { [weak self] granted in
            guard let self = self, granted else {
                let error = NSError(domain: "CameraManager", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Camera permission denied"])
                DispatchQueue.main.async {
                    self?.delegate?.cameraManagerDidFail(self!, error: error)
                }
                return
            }
            
            self.sessionQueue.async {
                if !self.isSessionConfigured {
                    self.configureCaptureSession()
                    self.isSessionConfigured = true
                }
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                    self.isSessionRunning = true
                }

                // Apply any desired settings now that the session/device exists
                self.applyZoom()
                self.applyTorch()
                
                DispatchQueue.main.async {
                    self.delegate?.cameraManagerDidStart(self)
                }
            }
        }
    }
    
    /// Stop the camera session
    func stopCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionRunning else { return }
            
            // Always turn torch off when stopping camera to avoid leaving hardware active.
            self.forceTorchOff()

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.isSessionRunning = false
        }
    }
    
    /// Set torch/flashlight state
    /// - Parameter enabled: Whether torch should be enabled
    func setTorch(enabled: Bool) {
        desiredTorchEnabled = enabled
        print("[CameraManager] Torch requested: \(enabled)")
        sessionQueue.async { [weak self] in
            self?.applyTorch()
        }
    }
    
    /// Set zoom level
    /// - Parameter level: The zoom level (clamped to device limits)
    func setZoom(level: CGFloat) {
        desiredZoomLevel = level
        sessionQueue.async { [weak self] in
            self?.applyZoom()
        }
    }
    
    /// Check if torch is available
    /// - Returns: True if torch is available
    func isTorchAvailable() -> Bool {
        return currentDevice?.hasTorch ?? false
    }
    
    /// Get the preview layer for displaying camera feed
    /// - Returns: The AVCaptureVideoPreviewLayer
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        // Implementation: Return preview layer
        return previewLayer
    }
    
    // MARK: - Private Setup Methods
    
    /// Configure the capture session
    private func configureCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        // Setup camera input
        guard setupCameraInput() else {
            captureSession.commitConfiguration()
            return
        }
        
        // Setup video output
        guard setupVideoOutput() else {
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.commitConfiguration()

        // Apply desired settings once input/output are configured
        applyZoom()
        applyTorch()
        
        // Setup preview layer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.setupPreviewLayer()
        }
    }
    
    /// Setup camera input
    /// - Returns: True if setup successful
    @discardableResult
    private func setupCameraInput() -> Bool {
        guard let device = getDefaultCameraDevice() else {
            print("[CameraManager] No camera device available")
            return false
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentDevice = device
                currentInput = input
                print("[CameraManager] Camera input added successfully")
                return true
            } else {
                print("[CameraManager] Cannot add camera input to session")
                return false
            }
        } catch {
            print("[CameraManager] Error creating camera input: \(error)")
            return false
        }
    }

    // MARK: - Apply desired settings

    private func applyTorch() {
        guard let device = currentDevice else {
            print("[CameraManager] ⚠️ applyTorch: no currentDevice yet")
            return
        }
        guard device.hasTorch else {
            print("[CameraManager] ⚠️ applyTorch: device hasTorch=false (\(device.localizedName))")
            return
        }

        print("[CameraManager] applyTorch -> desired=\(desiredTorchEnabled) device=\(device.localizedName) position=\(device.position.rawValue) currentMode=\(device.torchMode.rawValue) active=\(device.isTorchActive)")

        lockDeviceForConfiguration(device) { device in
            if self.desiredTorchEnabled {
                if device.isTorchModeSupported(.on) {
                    do {
                        try device.setTorchModeOn(level: self.desiredTorchLevel)
                        print("[CameraManager] ✅ Torch ON applied via setTorchModeOn(level:) on \(device.localizedName)")
                    } catch {
                        // Fallback
                        device.torchMode = .on
                        print("[CameraManager] ⚠️ Torch ON fallback (setTorchModeOn failed: \(error.localizedDescription))")
                    }
                } else {
                    device.torchMode = .on
                    print("[CameraManager] ⚠️ Torch ON fallback (mode .on not supported??) on \(device.localizedName)")
                }
            } else {
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                    print("[CameraManager] ✅ Torch OFF applied on \(device.localizedName)")
                } else {
                    device.torchMode = .off
                    print("[CameraManager] ⚠️ Torch OFF fallback (mode .off not supported??) on \(device.localizedName)")
                }
            }
        }

        print("[CameraManager] applyTorch done -> mode=\(device.torchMode.rawValue) active=\(device.isTorchActive)")
    }

    private func forceTorchOff() {
        guard let device = currentDevice, device.hasTorch else { return }
        lockDeviceForConfiguration(device) { device in
            if device.isTorchModeSupported(.off) {
                device.torchMode = .off
            } else {
                device.torchMode = .off
            }
        }
    }

    private func applyZoom() {
        guard let device = currentDevice else { return }
        lockDeviceForConfiguration(device) { device in
            let clampedZoom = min(max(self.desiredZoomLevel, device.minAvailableVideoZoomFactor),
                                  device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clampedZoom
        }
    }
    
    /// Setup video output
    /// - Returns: True if setup successful
    @discardableResult
    private func setupVideoOutput() -> Bool {
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoDataOutput = output
            print("[CameraManager] Video output added successfully")
            return true
        } else {
            print("[CameraManager] Cannot add video output to session")
            return false
        }
    }
    
    /// Setup preview layer
    private func setupPreviewLayer() {
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        previewLayer = preview
        print("[CameraManager] Preview layer created")
    }
    
    // MARK: - Camera Configuration
    
    /// Get the default camera device (back camera)
    /// - Returns: The camera device or nil
    private func getDefaultCameraDevice() -> AVCaptureDevice? {
        // Prefer a BACK camera that supports torch.
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera,
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )

        if let torchBack = discovery.devices.first(where: { $0.hasTorch }) {
            print("[CameraManager] ✅ Using back camera with torch: \(torchBack.localizedName)")
            return torchBack
        }

        if let anyBack = discovery.devices.first {
            print("[CameraManager] ⚠️ Back camera found but hasTorch=false: \(anyBack.localizedName)")
            return anyBack
        }

        // Fallback to any available video device
        print("[CameraManager] ⚠️ No back camera available, using default(for: .video)")
        if let device = AVCaptureDevice.default(for: .video) {
            print("[CameraManager] Default camera position: \(device.position.rawValue) - \(device.localizedName) (hasTorch=\(device.hasTorch))")
            return device
        }

        print("[CameraManager] ❌ No camera device available!")
        return nil
    }
    
    /// Check camera permissions
    /// - Parameter completion: Callback with permission status
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
            
        case .denied, .restricted:
            print("[CameraManager] Camera permission denied or restricted")
            completion(false)
            
        @unknown default:
            completion(false)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Lock device for configuration
    /// - Parameter device: The device to lock
    /// - Parameter configurator: Configuration block
    private func lockDeviceForConfiguration(_ device: AVCaptureDevice,
                                           configurator: (AVCaptureDevice) -> Void) {
        do {
            try device.lockForConfiguration()
            configurator(device)
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] Failed to lock device for configuration: \(error)")
        }
    }
    
    deinit {
        stopCamera()
        print("[CameraManager] Deinitialized")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Forward sample buffer to delegate for processing
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
    
    func captureOutput(_ output: AVCaptureOutput,
                      didDrop sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Optionally log dropped frames for debugging
        // print("[CameraManager] Dropped frame")
    }
}

