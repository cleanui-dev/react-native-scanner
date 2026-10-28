//
//  ScannerViewImpl.swift
//  react-native-scanner
//
//  Main scanner view implementation
//

import UIKit
import AVFoundation
import Vision

/// Main scanner view that manages camera, detection, and overlays
@objc(ScannerViewImpl)
@objcMembers
class ScannerViewImpl: UIView {
    
    // MARK: - Public Properties
    
    /// Delegate for scanner events
    @objc public weak var delegate: ScannerViewDelegate?
    
    // MARK: - Private Properties
    
    /// Camera manager for AVFoundation operations
    private let cameraManager: CameraManager
    
    /// Barcode detection manager for Vision framework operations
    private let barcodeDetectionManager: BarcodeDetectionManager
    
    /// Frame manager for barcode frame lifecycle
    private let frameManager: BarcodeFrameManager
    
    /// Overlay view for focus area
    private let focusAreaOverlay: FocusAreaOverlayView
    
    /// Overlay view for barcode frames
    private let barcodeFrameOverlay: BarcodeFrameOverlayView
    
    /// Reference to the preview layer
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Configuration state
    private var focusAreaConfig: FocusAreaConfig
    private var barcodeFramesConfig: BarcodeFramesConfig
    private var scanStrategy: BarcodeScanStrategy
    private var isPaused: Bool
    private var keepScreenOn: Bool
    private var isPreviewLayerAdded: Bool = false

    // Remember torch state so we can re-apply after camera starts
    private var requestedTorchEnabled: Bool = false

    // Track visibility so we can stop the camera when this view isn't on-screen (no JS hooks needed)
    private var isViewVisible: Bool = false
    
    // Debounce mechanism to prevent multiple rapid barcode detections
    private var lastBarcodeEmissionTime: TimeInterval = 0
    private var barcodeEmissionDebounceInterval: TimeInterval = 0.5 // Default 500ms debounce

    // Zoom state (main thread). baseZoom is where auto-zoom returns to: the zoom prop,
    // raised to the minimum-focus zoom when auto-zoom is on, or the last pinch.
    private var userZoom: CGFloat = 1.0
    private var pinchedZoom: CGFloat?
    private var baseZoom: CGFloat = 1.0
    private var currentZoom: CGFloat = 1.0
    private var autoZoomEnabled: Bool = true
    private var maxAutoZoom: CGFloat = 5.0
    private var lastAutoZoomTime: TimeInterval = 0
    private var lastCandidateTime: TimeInterval = 0
    private var zoomRampEndTime: TimeInterval = 0

    // Gestures
    private var pinchStartZoom: CGFloat = 1.0
    private var isPinching: Bool = false
    private var focusRevertWorkItem: DispatchWorkItem?
    private var lastTapFocusTime: TimeInterval = 0
    private lazy var pinchGesture: UIPinchGestureRecognizer = {
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        gesture.cancelsTouchesInView = false
        return gesture
    }()
    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    /// Auto-zoom tuning. "Fill" = barcode size relative to the scan region (focus area or view).
    private enum AutoZoom {
        static let minFill: CGFloat = 0.25 // smaller than this -> zoom in
        static let maxFill: CGFloat = 0.9 // larger than this -> zoom out
        static let targetFill: CGFloat = 0.5
        static let zoomOutStep: CGFloat = 0.75 // max zoom-out per step when a barcode overflows the region
        static let regionInset: CGFloat = 0.05 // keep zoomed barcode this far inside the region
        static let minStep: CGFloat = 0.1 // ignore changes smaller than 10%
        static let cooldown: TimeInterval = 0.8 // let focus settle before adjusting again
        static let resetDelay: TimeInterval = 2.5 // no barcode in region for this long -> zoom back
        static let rampDuration: TimeInterval = 0.4
        static let maxMinimumFocusZoom: CGFloat = 3.0
        static let tapFocusDuration: TimeInterval = 3.0
    }
    
    // MARK: - Initialization
    
    @objc override init(frame: CGRect) {
        // Initialize managers and configuration
        self.cameraManager = CameraManager()
        self.barcodeDetectionManager = BarcodeDetectionManager()
        self.frameManager = BarcodeFrameManager()
        self.focusAreaOverlay = FocusAreaOverlayView()
        self.barcodeFrameOverlay = BarcodeFrameOverlayView()
        
        // Initialize configuration with defaults
        self.focusAreaConfig = .defaultConfig
        self.barcodeFramesConfig = .defaultConfig
        self.scanStrategy = .defaultStrategy
        self.isPaused = false
        self.keepScreenOn = true
        
        super.init(frame: frame)
        
        print("[ScannerViewImpl] 🚀 Initializing ScannerViewImpl with frame: \(frame)")
        setupView()
        setupDelegates()
        setupCamera()
        print("[ScannerViewImpl] ✅ ScannerViewImpl initialization complete")
    }
    
    @objc convenience init(frame: CGRect, delegate: ScannerViewDelegate?) {
        self.init(frame: frame)
        self.delegate = delegate
        print("[ScannerViewImpl] ✅ Delegate set via convenience initializer")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup Methods
    
    /// Setup the view hierarchy and layout
    private func setupView() {
        backgroundColor = .black
        
        // Add subviews in order (bottom to top)
        addSubview(focusAreaOverlay)
        addSubview(barcodeFrameOverlay)
        
        // Configure autoresizing masks
        focusAreaOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        barcodeFrameOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addGestureRecognizer(pinchGesture)
        addGestureRecognizer(tapGesture)
        
        print("[ScannerViewImpl] View hierarchy setup complete")
    }
    
    /// Setup delegates for all managers
    private func setupDelegates() {
        cameraManager.delegate = self
        barcodeDetectionManager.delegate = self
        frameManager.delegate = self
        
        // Setup frame manager callback
        frameManager.onFramesChanged = { [weak self] frames in
            self?.barcodeFrameOverlay.setBarcodeBoxes(frames)
        }
        
        print("[ScannerViewImpl] Delegates configured")
    }
    
    /// Setup the camera and start preview
    private func setupCamera() {
        // Don't start camera here. Fabric/Navigation may create the view before it is on-screen.
        // We'll start/stop based on actual visibility in `updateVisibility`.
        print("[ScannerViewImpl] 📷 Camera will start when view becomes visible")
    }
    
    // MARK: - Public Configuration Methods
    
    /// Set barcode formats to detect
    /// - Parameter formats: Array of format strings
    @objc func setBarcodeTypes(_ formats: [String]) {
        let barcodeFormats = formats.compactMap { BarcodeFormat(rawValue: $0) }
        barcodeDetectionManager.setBarcodeFormats(barcodeFormats)
        print("[ScannerViewImpl] Barcode types set: \(formats)")
    }
    
    /// Configure focus area
    /// - Parameter config: Focus area configuration dictionary
    @objc func configureFocusArea(_ config: [String: Any]) {
        focusAreaConfig = FocusAreaConfig.from(dict: config)
        focusAreaOverlay.updateFocusArea(config: focusAreaConfig)
        // Update camera focus point to focus area center for better small barcode scanning
        setupFocusPointOfInterest()
        // The minimum-focus zoom depends on the focus area size
        updateBaseZoom(animated: false)
        print("[ScannerViewImpl] Focus area configured")
    }
    
    /// Configure barcode frames
    /// - Parameter config: Barcode frames configuration dictionary
    @objc func configureBarcodeFrames(_ config: [String: Any]) {
        barcodeFramesConfig = BarcodeFramesConfig.from(dict: config)
        barcodeFrameOverlay.updateBarcodeFrames(config: barcodeFramesConfig)
        print("[ScannerViewImpl] Barcode frames configured")
    }
    
    /// Set torch enabled/disabled
    /// - Parameter enabled: Whether torch should be enabled
    @objc func setTorchEnabled(_ enabled: NSNumber) {
        let value = enabled.boolValue
        print("[ScannerViewImpl] Torch requested: \(value)")
        requestedTorchEnabled = value
        cameraManager.setTorch(enabled: value)
    }
    
    /// Set zoom level
    /// - Parameter zoom: The zoom level
    @objc func setZoomLevel(_ zoom: NSNumber) {
        userZoom = max(CGFloat(zoom.doubleValue), 1.0)
        pinchedZoom = nil
        updateBaseZoom(animated: false, emit: false)
    }

    /// Enable/disable automatic zoom
    @objc func setAutoZoom(_ enabled: NSNumber) {
        autoZoomEnabled = enabled.boolValue
        updateBaseZoom(animated: true)
        print("[ScannerViewImpl] Auto-zoom \(autoZoomEnabled ? "enabled" : "disabled")")
    }

    /// Set the maximum zoom auto-zoom may reach
    @objc func setMaxAutoZoom(_ value: NSNumber) {
        maxAutoZoom = max(CGFloat(value.doubleValue), 1.0)
    }

    /// Enable/disable pinch-to-zoom
    @objc func setEnablePinchToZoom(_ enabled: NSNumber) {
        pinchGesture.isEnabled = enabled.boolValue
    }

    /// Enable/disable tap-to-focus
    @objc func setEnableTapToFocus(_ enabled: NSNumber) {
        tapGesture.isEnabled = enabled.boolValue
    }
    
    /// Pause or resume scanning
    /// - Parameter paused: Whether scanning should be paused
    @objc func setPauseScanning(_ paused: NSNumber) {
        let value = paused.boolValue
        isPaused = value
        if value {
            barcodeDetectionManager.pauseScanning()
            frameManager.clearAllFrames()
            // Reset debounce timer when pausing to prevent stale emissions
            lastBarcodeEmissionTime = 0
        } else {
            barcodeDetectionManager.resumeScanning()
            // Reset debounce timer when resuming to allow immediate detection
            lastBarcodeEmissionTime = 0
        }
        print("[ScannerViewImpl] Scanning \(value ? "paused" : "resumed")")
    }
    
    /// Set scan strategy
    /// - Parameter strategy: Strategy name as string
    @objc func setBarcodeScanStrategy(_ strategy: String) {
        if let scanStrat = BarcodeScanStrategy(rawValue: strategy) {
            scanStrategy = scanStrat
            barcodeDetectionManager.setScanStrategy(scanStrat)
            print("[ScannerViewImpl] Scan strategy set to: \(strategy)")
        }
    }
    
    /// Set keep screen on
    /// - Parameter keepOn: Whether to keep screen on
    @objc func setKeepScreenOn(_ keepOn: NSNumber) {
        let value = keepOn.boolValue
        keepScreenOn = value
        UIApplication.shared.isIdleTimerDisabled = value
        print("[ScannerViewImpl] Keep screen on: \(value)")
    }
    
    /// Set barcode emission debounce interval
    /// - Parameter interval: Minimum interval in seconds between barcode emissions (0 to disable)
    @objc func setBarcodeEmissionInterval(_ interval: NSNumber) {
        let value = interval.doubleValue
        barcodeEmissionDebounceInterval = max(0.0, value) // Ensure non-negative
        print("[ScannerViewImpl] Barcode emission interval set to: \(barcodeEmissionDebounceInterval)s")
    }
    
    // MARK: - Lifecycle Methods
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        print("[ScannerViewImpl] 📐 layoutSubviews called with bounds: \(bounds)")
        
        // Add preview layer if we have a valid frame and haven't added it yet
        if !isPreviewLayerAdded && bounds.width > 0 && bounds.height > 0 {
            if let preview = cameraManager.getPreviewLayer() {
                self.previewLayer = preview
                preview.frame = bounds
                layer.insertSublayer(preview, at: 0)
                isPreviewLayerAdded = true
                print("[ScannerViewImpl] ✅ Preview layer added in layoutSubviews with frame: \(bounds)")
            } else {
                print("[ScannerViewImpl] ⚠️ Preview layer not ready yet in layoutSubviews")
            }
        }
        
        // Update preview layer frame if already added
        if isPreviewLayerAdded {
            previewLayer?.frame = bounds
        }
        
        // Update overlay frames
        focusAreaOverlay.frame = bounds
        barcodeFrameOverlay.frame = bounds
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()

        let nowVisible = (self.window != nil) && !self.isHidden && self.alpha > 0.01
        updateVisibility(nowVisible)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        let nowVisible = (self.window != nil) && !self.isHidden && self.alpha > 0.01
        updateVisibility(nowVisible)
    }

    override var isHidden: Bool {
        didSet {
            let nowVisible = (self.window != nil) && !self.isHidden && self.alpha > 0.01
            updateVisibility(nowVisible)
        }
    }

    override var alpha: CGFloat {
        didSet {
            let nowVisible = (self.window != nil) && !self.isHidden && self.alpha > 0.01
            updateVisibility(nowVisible)
        }
    }

    private func updateVisibility(_ visible: Bool) {
        guard visible != isViewVisible else { return }
        isViewVisible = visible

        if visible {
            print("[ScannerViewImpl] 👁️ View became visible -> starting camera")
            if keepScreenOn {
                UIApplication.shared.isIdleTimerDisabled = true
            }
            cameraManager.startCamera()
        } else {
            print("[ScannerViewImpl] 🙈 View not visible -> stopping camera")
            cameraManager.stopCamera()
            // release keep-screen-on when off-screen
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    deinit {
        focusRevertWorkItem?.cancel()
        cameraManager.stopCamera()
        frameManager.shutdown()
        UIApplication.shared.isIdleTimerDisabled = false
        print("[ScannerViewImpl] Deinitialized")
    }
    
    // MARK: - Private Helper Methods
    
    /// Process detected barcodes according to strategy and filters
    /// - Parameter observations: Raw barcode observations from Vision
    /// - Returns: Filtered and processed barcode results
    private func processBarcodeObservations(_ observations: [VNBarcodeObservation]) -> [BarcodeDetectionResult] {
        guard !observations.isEmpty else { return [] }
        
        // Step 1: Filter by focus area if enabled
        let filteredObservations = filterByFocusArea(observations)
        guard !filteredObservations.isEmpty else { return [] }
        
        // Step 2: Apply scan strategy
        let strategyObservations = applyScanStrategy(filteredObservations)
        guard !strategyObservations.isEmpty else { return [] }
        
        // Step 3: Transform coordinates and create results
        var results: [BarcodeDetectionResult] = []
        for observation in strategyObservations {
            // Transform bounding box from Vision to View coordinates
            let viewRect = CoordinateTransformer.transformVisionRectToViewRect(
                observation.boundingBox,
                viewSize: bounds.size,
                previewLayer: previewLayer
            )
            
            // Get the barcode format string
            let formatString = observation.symbology.rawValue
            
            // Create result
            if let result = BarcodeDetectionResult.from(
                observation: observation,
                boundingBox: viewRect,
                format: formatString
            ) {
                results.append(result)
            }
        }
        
        return results
    }
    
    /// Filter barcodes by focus area if enabled
    /// - Parameter observations: Barcode observations to filter
    /// - Returns: Filtered observations
    private func filterByFocusArea(_ observations: [VNBarcodeObservation]) -> [VNBarcodeObservation] {
        guard focusAreaConfig.enabled, let focusRect = focusAreaOverlay.getFocusAreaFrame() else {
            return observations
        }
        
        return observations.filter { observation in
            // Transform barcode rect to view coordinates
            let viewRect = CoordinateTransformer.transformVisionRectToViewRect(
                observation.boundingBox,
                viewSize: bounds.size,
                previewLayer: previewLayer
            )
            
            // Check if barcode is within focus area
            return focusRect.contains(viewRect)
        }
    }
    
    /// Apply scan strategy to barcode observations
    /// - Parameter observations: Barcode observations
    /// - Returns: Processed observations according to strategy
    private func applyScanStrategy(_ observations: [VNBarcodeObservation]) -> [VNBarcodeObservation] {
        guard !observations.isEmpty else { return [] }
        
        switch scanStrategy {
        case .one:
            // Return only the first barcode
            return [observations[0]]
            
        case .all:
            // Return all barcodes
            return observations
            
        case .biggest:
            // Return only the largest barcode by area
            let observationsWithArea = observations.compactMap { observation -> (VNBarcodeObservation, CGFloat)? in
                let rect = observation.boundingBox
                let area = rect.width * rect.height
                return (observation, area)
            }
            
            if let biggest = observationsWithArea.max(by: { $0.1 < $1.1 }) {
                return [biggest.0]
            }
            return []
            
        case .sortByBiggest:
            // Sort all barcodes by area (largest first)
            let observationsWithArea = observations.compactMap { observation -> (VNBarcodeObservation, CGFloat)? in
                let rect = observation.boundingBox
                let area = rect.width * rect.height
                return (observation, area)
            }
            
            return observationsWithArea
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }
    }
    
    /// Update barcode frame display
    /// - Parameter observations: Barcode observations to display
    private func updateBarcodeFrameDisplay(_ observations: [VNBarcodeObservation]) {
        guard barcodeFramesConfig.enabled else {
            frameManager.clearAllFrames()
            return
        }

        let focusRect = focusAreaOverlay.getFocusAreaFrame()
        
        var frameDict: [String: CGRect] = [:]
        
        for observation in observations {
            guard let barcodeValue = observation.payloadStringValue else { continue }
            
            // Transform to view coordinates
            let viewRect = CoordinateTransformer.transformVisionRectToViewRect(
                observation.boundingBox,
                viewSize: bounds.size,
                previewLayer: previewLayer
            )
            
            // Filter by focus area if onlyInFocusArea is enabled
            if barcodeFramesConfig.onlyInFocusArea, let focusRect {
                if focusRect.contains(viewRect) {
                    frameDict[barcodeValue] = viewRect
                }
            } else {
                frameDict[barcodeValue] = viewRect
            }
        }
        
        frameManager.updateBarcodeFrames(frameDict)
    }
    
    /// Emit barcodes detected event to React Native
    /// - Parameter results: Detected barcode results
    private func emitBarcodesDetected(_ results: [BarcodeDetectionResult]) {
        // Debounce: Prevent rapid duplicate emissions
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastEmission = currentTime - lastBarcodeEmissionTime
        
        // If we've emitted recently (within debounce interval), skip this emission
        // This prevents multiple alerts when pauseScanning is set but detection callbacks are still in flight
        guard timeSinceLastEmission >= barcodeEmissionDebounceInterval else {
            print("[ScannerViewImpl] ⏭️ Skipping barcode emission (debounced, last emission was \(timeSinceLastEmission)s ago)")
            return
        }
        
        lastBarcodeEmissionTime = currentTime
        let barcodesArray = results.map { $0.toDictionary() }
        delegate?.scannerDidDetectBarcodes(barcodesArray)
        print("[ScannerViewImpl] ✅ Barcode emitted (debounced)")
    }
    
    /// Emit error event to React Native
    /// - Parameter error: The error that occurred
    private func emitError(_ error: ScannerError) {
        delegate?.scannerDidEncounterError(error.toDictionary())
    }
    
    /// Emit load event to React Native
    /// - Parameter success: Whether loading was successful
    /// - Parameter error: Optional error message
    private func emitLoadEvent(success: Bool, error: String? = nil) {
        let payload = LoadEventPayload(success: success, error: error)
        delegate?.scannerDidLoad(payload.toDictionary())
    }
}

// MARK: - Zoom & Gestures

extension ScannerViewImpl {
    /// Region (in view coordinates) used for auto-zoom and focus: the focus area when it is
    /// enabled or shown, otherwise the whole view.
    private func scanRegion() -> CGRect? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        if focusAreaConfig.enabled || focusAreaConfig.showOverlay,
           let focusRect = focusAreaOverlay.getFocusAreaFrame() {
            return focusRect
        }
        return bounds
    }

    private func clampZoom(_ zoom: CGFloat) -> CGFloat {
        guard let limits = cameraManager.zoomLimits() else { return max(zoom, 1.0) }
        return min(max(zoom, limits.min), limits.max)
    }

    private func setZoom(_ zoom: CGFloat, animated: Bool) {
        let clamped = clampZoom(zoom)
        currentZoom = clamped
        if animated {
            cameraManager.rampZoom(to: clamped)
            zoomRampEndTime = CACurrentMediaTime() + AutoZoom.rampDuration
        } else {
            cameraManager.setZoom(level: clamped)
        }
    }

    /// Recompute the zoom auto-zoom rests at and apply it.
    /// - Parameter emit: report the change via onZoomChange (off for changes made through the zoom prop)
    private func updateBaseZoom(animated: Bool, emit: Bool = true) {
        if let pinchedZoom {
            baseZoom = pinchedZoom
        } else {
            var zoom = userZoom
            if autoZoomEnabled, let minimumFocusZoom = minimumFocusZoom() {
                zoom = max(zoom, minimumFocusZoom)
            }
            baseZoom = clampZoom(zoom)
        }
        let changed = abs(baseZoom - currentZoom) > 0.001
        setZoom(baseZoom, animated: animated)
        // Report zoom the app didn't set directly (e.g. raised to the minimum-focus zoom)
        if changed && emit {
            emitZoomChange(baseZoom)
        }
    }

    /// Zoom needed so a small code filling the scan region is still at a focusable distance.
    private func minimumFocusZoom() -> CGFloat? {
        guard let region = scanRegion() else { return nil }
        // The preview (aspect fill, portrait) shows the sensor's long side along the view's long side
        let longSide = max(bounds.width, bounds.height)
        guard let factor = cameraManager.minimumFocusZoomFactor(fillFraction: region.width / longSide) else {
            return nil
        }
        return min(factor, min(maxAutoZoom, AutoZoom.maxMinimumFocusZoom))
    }

    /// Adjust zoom based on barcodes detected inside the scan region.
    ///
    /// Only barcodes whose center lies in the scan region (the focus area when enabled or
    /// shown) are considered, so a barcode outside the focus area never drives the zoom.
    /// Because zoom scales around the preview center, the zoom-in factor is also capped so the
    /// target stays inside the region after zooming (important for off-center focus areas).
    ///
    /// Unlike ML Kit, Vision only returns barcodes it could decode, so on iOS this mostly backs
    /// off when a decoded barcode overflows the focus area. A decoded barcode that is emitted
    /// is left alone (zooming in right after a successful scan would only make the preview jump).
    /// Zoom-in only happens for observations without a payload, if Vision reports any.
    ///
    /// Must be called on the main thread.
    fileprivate func evaluateAutoZoom(_ observations: [VNBarcodeObservation]) {
        guard autoZoomEnabled, !isPinching, !isPaused, previewLayer != nil,
              let region = scanRegion() else { return }
        let now = CACurrentMediaTime()

        let candidates = observations
            .map { observation in
                (observation, CoordinateTransformer.transformVisionRectToViewRect(
                    observation.boundingBox,
                    viewSize: bounds.size,
                    previewLayer: previewLayer
                ))
            }
            .filter { region.contains(CGPoint(x: $0.1.midX, y: $0.1.midY)) }

        guard let (targetObservation, target) = candidates.max(by: {
            $0.1.width * $0.1.height < $1.1.width * $1.1.height
        }) else {
            // Nothing to scan in the region for a while: return to the base zoom
            if currentZoom > baseZoom * (1 + AutoZoom.minStep),
               now - lastCandidateTime > AutoZoom.resetDelay,
               now > zoomRampEndTime {
                lastCandidateTime = now
                setZoom(baseZoom, animated: true)
                emitZoomChange(baseZoom)
            }
            return
        }
        lastCandidateTime = now

        // A decoded barcode that will actually be emitted (fully inside the focus area when
        // filtering is on) means this zoom works: leave it alone
        if candidates.contains(where: { $0.0.payloadStringValue != nil && wouldBeEmitted($0.1) }) {
            return
        }
        guard now > zoomRampEndTime, now - lastAutoZoomTime > AutoZoom.cooldown else { return }

        let fill = max(target.width / region.width, target.height / region.height)
        guard fill > 0 else { return }

        let factor: CGFloat
        if !region.contains(target) && currentZoom > baseZoom {
            // Barcode spills past the region (and is filtered out): back off
            factor = min(AutoZoom.targetFill / fill, AutoZoom.zoomOutStep)
        } else if fill < AutoZoom.minFill && targetObservation.payloadStringValue == nil {
            factor = min(AutoZoom.targetFill / fill, maxZoomFactorKeepingInside(target, region: region))
        } else if fill > AutoZoom.maxFill && currentZoom > baseZoom {
            factor = AutoZoom.targetFill / fill
        } else {
            return
        }

        let deviceMax = cameraManager.zoomLimits()?.max ?? maxAutoZoom
        let upperBound = max(baseZoom, min(maxAutoZoom, deviceMax))
        let newZoom = min(max(currentZoom * factor, baseZoom), upperBound)
        guard abs(newZoom - currentZoom) / currentZoom >= AutoZoom.minStep else { return }

        lastAutoZoomTime = now
        print("[ScannerViewImpl] Auto-zoom: \(currentZoom) -> \(newZoom)")
        setZoom(newZoom, animated: true)
        emitZoomChange(newZoom)
        // Refocus on the region once the ramp is done (unless the user just tapped to focus)
        DispatchQueue.main.asyncAfter(deadline: .now() + AutoZoom.rampDuration) { [weak self] in
            self?.setupFocusPointOfInterest(respectingTapFocus: true)
        }
    }

    /// Whether a decoded barcode at `rect` (view coordinates) passes `filterByFocusArea`.
    private func wouldBeEmitted(_ rect: CGRect) -> Bool {
        guard focusAreaConfig.enabled, let focusRect = focusAreaOverlay.getFocusAreaFrame() else {
            return true
        }
        return focusRect.contains(rect)
    }

    /// Largest relative zoom factor that keeps `box` inside `region` (inset by a margin),
    /// given that zoom scales around the center of the preview.
    private func maxZoomFactorKeepingInside(_ box: CGRect, region: CGRect) -> CGFloat {
        let cx = bounds.midX
        let cy = bounds.midY
        let limits = region.insetBy(dx: region.width * AutoZoom.regionInset,
                                    dy: region.height * AutoZoom.regionInset)

        var limit = CGFloat.greatestFiniteMagnitude
        if box.minX < cx { limit = min(limit, (cx - limits.minX) / (cx - box.minX)) }
        if box.maxX > cx { limit = min(limit, (limits.maxX - cx) / (box.maxX - cx)) }
        if box.minY < cy { limit = min(limit, (cy - limits.minY) / (cy - box.minY)) }
        if box.maxY > cy { limit = min(limit, (limits.maxY - cy) / (box.maxY - cy)) }
        // A limit below 1 means the box already sits at/over the edge: don't zoom in
        return max(limit, 1.0)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPinching = true
            pinchStartZoom = currentZoom
        case .changed:
            setZoom(pinchStartZoom * gesture.scale, animated: false)
        case .ended, .cancelled, .failed:
            isPinching = false
            // A pinch is the user's chosen zoom: auto-zoom resets back to it
            pinchedZoom = currentZoom
            baseZoom = currentZoom
            emitZoomChange(currentZoom)
            setupFocusPointOfInterest(respectingTapFocus: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let previewLayer = previewLayer else { return }
        let point = gesture.location(in: self)
        let pointInLayer = previewLayer.convert(point, from: layer)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: pointInLayer)
        cameraManager.setFocusPointOfInterest(normalizedX: devicePoint.x, normalizedY: devicePoint.y)
        lastTapFocusTime = CACurrentMediaTime()

        // Return focus to the scan region after a while (matches Android's auto-cancel)
        focusRevertWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setupFocusPointOfInterest()
        }
        focusRevertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + AutoZoom.tapFocusDuration, execute: workItem)
    }

    private func emitZoomChange(_ zoom: CGFloat) {
        delegate?.scannerDidChangeZoom?(["zoom": Double(zoom)])
    }
}

// MARK: - CameraManagerDelegate

extension ScannerViewImpl: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        // Don't process if scanning is paused
        guard !isPaused else { return }
        
        // Pass sample buffer to barcode detection
        barcodeDetectionManager.detectBarcodes(in: sampleBuffer) { [weak self] observations in
            guard let self = self, !self.isPaused else { return }
            
            // Process observations
            let results = self.processBarcodeObservations(observations)
            
            // Update barcode frames display
            self.updateBarcodeFrameDisplay(observations)

            DispatchQueue.main.async { [weak self] in
                self?.evaluateAutoZoom(observations)
            }
            
            // Emit results if any
            if !results.isEmpty {
                self.emitBarcodesDetected(results)
            }
        }
    }
    
    func cameraManagerDidFail(_ manager: CameraManager, error: Error) {
        print("[ScannerViewImpl] Camera failed: \(error.localizedDescription)")
        let scannerError = ScannerError.from(
            code: .cameraInitializationFailed,
            message: error.localizedDescription
        )
        emitError(scannerError)
    }
    
    func cameraManagerDidStart(_ manager: CameraManager) {
        print("[ScannerViewImpl] ✅ Camera started successfully")

        // Re-apply torch after the session is fully running (fixes "torch set too early" cases)
        manager.setTorch(enabled: requestedTorchEnabled)
        
        // Try to add preview layer on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check bounds multiple times with delay to catch layout
            self.attemptToAddPreviewLayer(attempt: 0)
            
            // Set focus point of interest (center or focus area center) for better small barcode/QR scanning
            self.setupFocusPointOfInterest()

            // Apply the base zoom now that device limits / focus distance are known
            self.updateBaseZoom(animated: false)
            
            self.emitLoadEvent(success: true)
        }
    }
    
    /// Set the camera focus point of interest to the focus area center (or screen center)
    /// so continuous autofocus prioritizes that region and small barcodes/QR codes stay sharp.
    /// - Parameter respectingTapFocus: skip if the user tapped to focus within the last few seconds
    private func setupFocusPointOfInterest(respectingTapFocus: Bool = false) {
        if respectingTapFocus && CACurrentMediaTime() - lastTapFocusTime < AutoZoom.tapFocusDuration {
            return
        }
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let previewLayer = self.previewLayer else { return }

        // 1) Get center point in view coordinates (either focus area center or view center)
        guard let region = scanRegion() else { return }
        let centerPointInView = CGPoint(x: region.midX, y: region.midY)

        // 2) Convert from view/layer space into device focus coordinates using AVFoundation helper
        let pointInLayer = previewLayer.convert(centerPointInView, from: self.layer)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: pointInLayer)

        // 3) Pass device-normalized coordinates (0,0 top-left, 1,1 bottom-right) to camera manager
        cameraManager.setFocusPointOfInterest(
            normalizedX: devicePoint.x,
            normalizedY: devicePoint.y
        )
    }
    
    private func attemptToAddPreviewLayer(attempt: Int) {
        guard !isPreviewLayerAdded else { return }
        
        if self.bounds.width > 0 && self.bounds.height > 0 {
            if let preview = self.cameraManager.getPreviewLayer() {
                self.previewLayer = preview
                preview.frame = self.bounds
                self.layer.insertSublayer(preview, at: 0)
                self.isPreviewLayerAdded = true
                print("[ScannerViewImpl] ✅ Preview layer added with frame: \(self.bounds)")
            }
        } else if attempt < 10 {
            // Try again after a short delay (max 10 attempts = ~2 seconds)
            print("[ScannerViewImpl] ⏳ Attempt \(attempt + 1): Waiting for valid bounds (current: \(self.bounds))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.attemptToAddPreviewLayer(attempt: attempt + 1)
            }
        } else {
            print("[ScannerViewImpl] ❌ Failed to add preview layer after 10 attempts - bounds never became valid")
        }
    }
}

// MARK: - BarcodeDetectionDelegate

extension ScannerViewImpl: BarcodeDetectionDelegate {
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager,
                                 didDetect observations: [VNBarcodeObservation]) {
        // This is only called when using the delegate-based detection
        // We're using the completion-based approach in cameraManager:didOutput:
        // But we can handle it here as well if needed
    }
    
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager,
                                 didFailWith error: Error) {
        print("[ScannerViewImpl] Barcode detection failed: \(error.localizedDescription)")
        let scannerError = ScannerError.from(
            code: .barcodeDetectionFailed,
            message: error.localizedDescription
        )
        emitError(scannerError)
    }
}

// MARK: - BarcodeFrameManagerDelegate

extension ScannerViewImpl: BarcodeFrameManagerDelegate {
    func barcodeFrameManager(_ manager: BarcodeFrameManager,
                            didUpdateFrames frames: [CGRect]) {
        // Frames are automatically updated via the closure callback
        // This delegate method is here for additional functionality if needed
    }
}

