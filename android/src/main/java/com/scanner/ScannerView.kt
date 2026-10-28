package com.scanner

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.os.PowerManager
import android.os.SystemClock
import android.util.AttributeSet
import android.util.Log
import android.util.Rational
import android.util.Size
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.Surface
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.camera.core.*
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.CaptureRequestOptions
import android.hardware.camera2.CaptureRequest
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.facebook.react.bridge.*
import com.facebook.react.uimanager.ThemedReactContext
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import com.scanner.utils.BarcodeFrameManager
import com.scanner.views.FocusAreaView
import com.scanner.views.BarcodeFrameOverlayView
import androidx.core.graphics.toColorInt
import com.facebook.react.uimanager.events.RCTEventEmitter

class ScannerView : FrameLayout {
  companion object {
    const val TAG = "ScannerView"

    // Target resolution for barcode analysis. CameraX defaults ImageAnalysis to 640x480,
    // which is too low to decode small or distant barcodes. 4:3 matches the Preview default
    // so bounding box mapping onto the preview stays consistent.
    private val ANALYSIS_TARGET_SIZE = Size(1440, 1080)

    // Auto-zoom tuning. "Fill" = barcode size relative to the scan region (focus area or view).
    private const val AUTO_ZOOM_MIN_FILL = 0.25f // smaller than this -> zoom in
    private const val AUTO_ZOOM_MAX_FILL = 0.9f // larger than this (and undecodable) -> zoom out
    private const val AUTO_ZOOM_TARGET_FILL = 0.5f
    private const val AUTO_ZOOM_OUT_STEP = 0.75f // max zoom-out per step when a barcode overflows the region
    private const val AUTO_ZOOM_REGION_INSET = 0.05f // keep zoomed barcode this far inside the region
    private const val AUTO_ZOOM_MIN_STEP = 0.1f // ignore changes smaller than 10%
    private const val AUTO_ZOOM_COOLDOWN_MS = 800L // let focus settle before adjusting again
    private const val AUTO_ZOOM_RESET_DELAY_MS = 2500L // no barcode in region for this long -> zoom back
    private const val ZOOM_ANIMATION_MS = 250L
    private const val TAP_FOCUS_HOLD_MS = 3000L // automatic refocus won't override a tap for this long
  }

  private var cameraProvider: ProcessCameraProvider? = null
  private var camera: androidx.camera.core.Camera? = null
  private var imageAnalyzer: ImageAnalysis? = null
  private var preview: Preview? = null
  private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
  // Written on the main thread, read on the analysis thread
  @Volatile
  private var barcodeScanner = createBarcodeScanner(withPotentialBarcodes = true)
  private var previewView: PreviewView? = null
  private var overlayView: FocusAreaView? = null
  private var barcodeFrameOverlayView: BarcodeFrameOverlayView? = null

  // Frame configuration
  private var enableFrame: Boolean = false
  private var borderColor: Int = Color.TRANSPARENT
  private var tintColor: Int = Color.BLACK
  private var frameSize: FrameSize = FrameSize.Square(300)
  private var positionX: Float = 50f // Default center (50%)
  private var positionY: Float = 50f // Default center (50%)
  private var showBarcodeFramesOnlyInFrame: Boolean = false

  // Focus area and barcode frames configuration
  private var focusAreaEnabled: Boolean = false
  private var barcodeFramesEnabled: Boolean = false
  private var barcodeFramesColor: Int = Color.RED

  // React context for event emission
  private var reactContext: ThemedReactContext? = null

  private var zoom: Float = 1.0f

  // Zoom state. baseZoom is where auto-zoom returns to (zoom prop, or the last pinch).
  private var baseZoom: Float = 1.0f
  private var currentZoom: Float = 1.0f
  private var zoomAnimator: ValueAnimator? = null
  private var autoZoomEnabled: Boolean = true
  private var maxAutoZoom: Float = 5.0f
  private var lastAutoZoomTime: Long = 0
  private var lastCandidateTime: Long = 0

  // Gestures
  private var pinchToZoomEnabled: Boolean = true
  private var tapToFocusEnabled: Boolean = true
  private var isPinching: Boolean = false
  private var isMultiTouchGesture: Boolean = false
  private var lastTapFocusTime: Long = 0
  private val scaleGestureDetector = ScaleGestureDetector(
    context,
    object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
      override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
        isPinching = true
        zoomAnimator?.cancel()
        return true
      }

      override fun onScale(detector: ScaleGestureDetector): Boolean {
        val zoomState = camera?.cameraInfo?.zoomState?.value ?: return false
        val newZoom = (currentZoom * detector.scaleFactor)
          .coerceIn(zoomState.minZoomRatio, zoomState.maxZoomRatio)
        applyZoomRatio(newZoom)
        // A pinch is the user's chosen zoom: auto-zoom resets back to it
        baseZoom = newZoom
        return true
      }

      override fun onScaleEnd(detector: ScaleGestureDetector) {
        isPinching = false
        emitOnZoomChange(currentZoom)
        refocusOnScanRegion()
      }
    }
  )
  private val tapGestureDetector = GestureDetector(
    context,
    object : GestureDetector.SimpleOnGestureListener() {
      override fun onSingleTapUp(e: MotionEvent): Boolean {
        lastTapFocusTime = SystemClock.uptimeMillis()
        triggerAutoFocusAt(e.x, e.y)
        return true
      }
    }
  )
  private var torchEnabled: Boolean = false
  private var isScanningPaused: Boolean = false

  // Barcode scan strategy
  private var barcodeScanStrategy: String = "ALL"

  // Barcode frame management
  private val barcodeFrameManager = BarcodeFrameManager()

  // Wake lock and screen keep-awake
  private var wakeLock: PowerManager.WakeLock? = null
  private var keepScreenOn: Boolean = true

  // Debounce mechanism to prevent multiple rapid barcode detections
  private var lastBarcodeEmissionTime: Long = 0
  private var barcodeEmissionDebounceInterval: Long = 500 // Default 500ms debounce

  constructor(context: Context) : super(context) {
    initScannerView(context)
  }

  constructor(context: Context, attrs: AttributeSet?) : super(context, attrs) {
    initScannerView(context)
  }

  constructor(context: Context, attrs: AttributeSet?, defStyleAttr: Int) : super(
    context,
    attrs,
    defStyleAttr
  ) {
    initScannerView(context)
  }

  private fun initScannerView(context: Context) {
    if (context is ThemedReactContext) {
      reactContext = context
    }

    // Initialize wake lock
    initializeWakeLock()

    previewView = PreviewView(context).apply {
      layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
      scaleType = PreviewView.ScaleType.FILL_CENTER
      implementationMode = PreviewView.ImplementationMode.PERFORMANCE
      // setBackgroundColor(Color.RED) // Optional: for debugging layout
    }
    installHierarchyFitter(previewView!!)
    addView(previewView)

    // Create overlay view for frame drawing
    overlayView = FocusAreaView(context).apply {
      layoutParams = LayoutParams(
        LayoutParams.MATCH_PARENT,
        LayoutParams.MATCH_PARENT
      )
    }
    addView(overlayView)

    // Create overlay view for barcode frame drawing
    barcodeFrameOverlayView = BarcodeFrameOverlayView(context).apply {
      layoutParams = LayoutParams(
        LayoutParams.MATCH_PARENT,
        LayoutParams.MATCH_PARENT
      )
    }
    addView(barcodeFrameOverlayView)

    // Set up barcode frame manager
    setupBarcodeFrameManager()
  }

  private fun setupBarcodeFrameManager() {
    barcodeFrameManager.setOnFramesChangedListener {
      // Update the overlay view with current frames
      val currentFrames = barcodeFrameManager.getActiveFrames()
      barcodeFrameOverlayView?.setBarcodeBoxes(currentFrames)
    }
  }

  private fun initializeWakeLock() {
    val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    wakeLock = powerManager.newWakeLock(
      PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
      "ScannerView::WakeLock"
    )
    wakeLock?.setReferenceCounted(false)
  }

  private fun acquireWakeLock() {
    if (keepScreenOn && wakeLock?.isHeld == false) {
      wakeLock?.acquire()
      Log.d(TAG, "Wake lock acquired")
    }
  }

  private fun releaseWakeLock() {
    if (wakeLock?.isHeld == true) {
      wakeLock?.release()
      Log.d(TAG, "Wake lock released")
    }
  }

  private fun updateKeepScreenOn(keepOn: Boolean) {
    keepScreenOn = keepOn
    if (keepOn) {
      // Set FLAG_KEEP_SCREEN_ON on the activity window
      val activity = reactContext?.currentActivity
      activity?.window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      acquireWakeLock()
    } else {
      // Remove FLAG_KEEP_SCREEN_ON from the activity window
      val activity = reactContext?.currentActivity
      activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
      releaseWakeLock()
    }
    Log.d(TAG, "Keep screen on: $keepOn")
  }

  private fun installHierarchyFitter(view: ViewGroup) {
    if (context is ThemedReactContext) { // only react-native setup
      view.setOnHierarchyChangeListener(object : OnHierarchyChangeListener {
        override fun onChildViewRemoved(parent: View?, child: View?) = Unit
        override fun onChildViewAdded(parent: View?, child: View?) {
          parent?.measure(
            MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY)
          )
          parent?.layout(0, 0, parent.measuredWidth, parent.measuredHeight)
        }
      })
    }
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    Log.d(TAG, "View attached to window, starting camera directly")
    startCamera()
  }

  override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
    stopCamera()
    // The view may be attached again (navigation, re-parenting): keep the frame manager alive
    // and only clear it. It is shut down for good in destroy().
    barcodeFrameManager.clearAllFrames()

    // Ensure wake lock is released when view is destroyed
    releaseWakeLock()
  }

  /**
   * Release resources for good. Called when React Native drops the view instance.
   */
  fun destroy() {
    stopCamera()
    barcodeFrameManager.shutdown()
    releaseWakeLock()
  }

  /**
   * ML Kit client. Potential barcodes (detected but not yet decodable) come back with a null
   * rawValue; they only drive auto-zoom and are never emitted, so they're only requested
   * while auto-zoom is on.
   */
  private fun createBarcodeScanner(withPotentialBarcodes: Boolean): BarcodeScanner {
    val options = BarcodeScannerOptions.Builder().apply {
      if (withPotentialBarcodes) enableAllPotentialBarcodes()
    }.build()
    return BarcodeScanning.getClient(options)
  }

  private fun startCamera() {
    Log.d(TAG, "Starting camera...")

    if (!hasCameraPermission()) {
      Log.e(TAG, "Camera permission not granted")
      emitOnScannerError("Camera permission not granted", "CAMERA_PERMISSION_DENIED")
      return
    }

    // Resources are released in stopCamera(); recreate them when the view is attached again
    if (cameraExecutor.isShutdown) {
      cameraExecutor = Executors.newSingleThreadExecutor()
      barcodeScanner = createBarcodeScanner(withPotentialBarcodes = autoZoomEnabled)
    }

    // Acquire wake lock when camera starts
    updateKeepScreenOn(true)

    val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
    cameraProviderFuture.addListener({
      try {
        cameraProvider = cameraProviderFuture.get()
        Log.d(TAG, "CameraProvider obtained")

        previewView?.post {
          Log.d(TAG, "Binding camera use cases on UI thread")
          bindCameraUseCases()
        }
      } catch (e: Exception) {
        Log.e(TAG, "Failed to initialize camera", e)
      }
//    }, ContextCompat.getMainExecutor(context))
    }, cameraExecutor)
  }

  private fun stopCamera() {
    if (cameraExecutor.isShutdown) return
    zoomAnimator?.cancel()
    camera?.cameraControl?.cancelFocusAndMetering()
    cameraProvider?.unbindAll()
    cameraExecutor.shutdown()
    barcodeScanner.close()

    // Release wake lock when camera stops
    updateKeepScreenOn(false)

    Log.e(TAG, "Camera stopped.")
  }

  private fun bindCameraUseCases() {
    val cameraProvider = cameraProvider ?: run {
      Log.e(TAG, "Camera provider not available for binding.")
      return
    }
    val lifecycleOwner = reactContext?.currentActivity as? LifecycleOwner ?: run {
      Log.e(TAG, "No LifecycleOwner available for binding.")
      return
    }

    // Unbind any previous use cases first
    cameraProvider.unbindAll()

    try {
      val surfaceProvider = previewView?.surfaceProvider
      if (surfaceProvider == null) {
        Log.e(TAG, "SurfaceProvider is null! Cannot bind.")
        return
      }

      // Preview
      preview = Preview.Builder()
        .setResolutionSelector(
          ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
            .build()
        )
        .setTargetRotation(previewView?.display?.rotation ?: Surface.ROTATION_0)
        .build()
        .also {
          it.setSurfaceProvider(surfaceProvider)
        }

      // Image Analysis
      imageAnalyzer = ImageAnalysis.Builder()
        .setResolutionSelector(
          ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
            .setResolutionStrategy(
              ResolutionStrategy(
                ANALYSIS_TARGET_SIZE,
                ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER
              )
            )
            .build()
        )
        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        .build()
        .also {
          it.setAnalyzer(cameraExecutor) { imageProxy ->
            processImage(imageProxy)
          }
        }

      // Select back camera as default
      val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

      // Create a ViewPort that matches the PreviewView
      val viewPort = ViewPort.Builder(
        Rational(previewView!!.width, previewView!!.height),
        previewView!!.display.rotation
      )
        .setScaleType(ViewPort.FILL_CENTER) // or FIT_CENTER as needed
        .build()

      // Create a UseCaseGroup with the ViewPort
      val useCaseGroup = UseCaseGroup.Builder()
        .addUseCase(preview!!)
        .addUseCase(imageAnalyzer!!)
        .setViewPort(viewPort)
        .build()

      // Bind use cases to camera
      camera = cameraProvider.bindToLifecycle(
        lifecycleOwner,
        cameraSelector,
        useCaseGroup
      )

      // Set up torch and zoom
      camera?.cameraControl?.enableTorch(torchEnabled)
      setZoom(zoom)

      // Set up continuous autofocus for better barcode scanning
      setupContinuousAutoFocus()

      // Set up auto-focus on frame center (if focus area is enabled)
      setupAutoFocusOnFrame()

      // Emit onLoad event after camera is successfully started
      emitOnLoadEvent(success = true)

    } catch (exc: Exception) {
      Log.e(TAG, "Use case binding failed", exc)
      // Emit onScannerError event for camera initialization failure
      emitOnScannerError(
        error = exc.message ?: "Camera binding failed",
        code = "CAMERA_INITIALIZATION_FAILED"
      )
    }
  }

  /**
   * Set up continuous autofocus mode for better barcode scanning.
   * This enables AF_MODE_CONTINUOUS_PICTURE which continuously adjusts focus,
   * making it much easier to scan barcodes at different distances.
   */
  private fun setupContinuousAutoFocus() {
    try {
      val camera2Control = camera?.cameraControl?.let { 
        Camera2CameraControl.from(it) 
      } ?: run {
        Log.w(TAG, "Camera2CameraControl not available")
        return
      }

      // Enable continuous autofocus mode
      camera2Control.captureRequestOptions = CaptureRequestOptions.Builder()
        .setCaptureRequestOption<Int>(
          CaptureRequest.CONTROL_AF_MODE,
          CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
        )
        .build()

      Log.d(TAG, "✅ Continuous autofocus enabled (AF_MODE_CONTINUOUS_PICTURE)")
    } catch (e: Exception) {
      Log.e(TAG, "Failed to setup continuous autofocus", e)
    }
  }

  /**
   * Set up autofocus on the focus area frame center.
   * This provides additional focus assistance when a focus area is defined.
   */
  private fun setupAutoFocusOnFrame() {
    refocusOnScanRegion()
  }

  /**
   * Region (in view coordinates) used for scanning and auto-zoom: the focus area when it is
   * enabled or shown, otherwise the whole preview.
   */
  private fun scanRegion(): RectF? {
    val view = previewView ?: return null
    if (view.width == 0 || view.height == 0) return null
    if (focusAreaEnabled || enableFrame) {
      overlayView?.frameRect?.let { return RectF(it) }
    }
    return RectF(0f, 0f, view.width.toFloat(), view.height.toFloat())
  }

  /**
   * Trigger autofocus/exposure at the center of the scan region.
   * Unless [force] is set, a recent tap-to-focus is respected.
   */
  private fun refocusOnScanRegion(force: Boolean = false) {
    if (!force && SystemClock.uptimeMillis() - lastTapFocusTime < TAP_FOCUS_HOLD_MS) return
    val region = scanRegion() ?: return
    triggerAutoFocusAt(region.centerX(), region.centerY())
  }

  /**
   * Trigger autofocus at a point in PreviewView coordinates (pixels).
   * After the auto-cancel duration the camera returns to continuous autofocus.
   */
  private fun triggerAutoFocusAt(x: Float, y: Float) {
    val meteringPointFactory = previewView?.meteringPointFactory ?: return
    val afPoint = meteringPointFactory.createPoint(x, y)

    val focusAction = FocusMeteringAction.Builder(
      afPoint,
      FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE
    )
      .setAutoCancelDuration(3, java.util.concurrent.TimeUnit.SECONDS)
      .build()

    camera?.cameraControl?.startFocusAndMetering(focusAction)
      ?.addListener({
        Log.d(TAG, "Auto-focus triggered at ($x, $y)")
      }, ContextCompat.getMainExecutor(context))
  }

  override fun onTouchEvent(event: MotionEvent): Boolean {
    if (!pinchToZoomEnabled && !tapToFocusEnabled) {
      return super.onTouchEvent(event)
    }
    if (pinchToZoomEnabled) {
      scaleGestureDetector.onTouchEvent(event)
    }
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> isMultiTouchGesture = false
      MotionEvent.ACTION_POINTER_DOWN -> if (!isMultiTouchGesture) {
        // A second finger means this gesture is a pinch, not a tap: cancel the pending tap
        isMultiTouchGesture = true
        val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
        tapGestureDetector.onTouchEvent(cancel)
        cancel.recycle()
      }
    }
    if (tapToFocusEnabled && !isMultiTouchGesture) {
      tapGestureDetector.onTouchEvent(event)
    }
    return true
  }

  // MARK: - Zoom

  private fun applyZoomRatio(ratio: Float) {
    currentZoom = ratio
    camera?.cameraControl?.setZoomRatio(ratio)
  }

  /**
   * Smoothly animate to the given zoom ratio, then refocus on the scan region.
   */
  private fun animateZoomTo(target: Float) {
    zoomAnimator?.cancel()
    zoomAnimator = ValueAnimator.ofFloat(currentZoom, target).apply {
      duration = ZOOM_ANIMATION_MS
      addUpdateListener { applyZoomRatio(it.animatedValue as Float) }
      addListener(object : android.animation.AnimatorListenerAdapter() {
        private var cancelled = false
        override fun onAnimationCancel(animation: android.animation.Animator) {
          cancelled = true
        }

        override fun onAnimationEnd(animation: android.animation.Animator) {
          if (cancelled) return
          emitOnZoomChange(target)
          refocusOnScanRegion()
        }
      })
      start()
    }
    Log.d(TAG, "Auto-zoom: $currentZoom -> $target")
  }

  /**
   * Adjust zoom based on barcodes detected inside the scan region.
   *
   * Only barcodes whose center lies in the scan region (the focus area when enabled) are
   * considered, so a barcode outside the focus area never drives the zoom. Because digital
   * zoom scales around the preview center, the zoom-in factor is also capped so the target
   * stays inside the region after zooming (important for off-center focus areas).
   *
   * Must be called on the main thread.
   */
  private fun evaluateAutoZoom(
    barcodes: List<Barcode>,
    transformationInfo: ImageAnalysisTransformationInfo
  ) {
    if (!autoZoomEnabled || isPinching || isScanningPaused) return
    val view = previewView ?: return
    val zoomState = camera?.cameraInfo?.zoomState?.value ?: return
    val region = scanRegion() ?: return
    val now = SystemClock.uptimeMillis()

    val candidates = barcodes.mapNotNull { barcode ->
      barcode.boundingBox?.let { box ->
        barcode to transformBarcodeBoundingBox(box, transformationInfo, view)
      }
    }.filter { (_, rect) -> region.contains(rect.centerX(), rect.centerY()) }

    if (candidates.isEmpty()) {
      // Nothing to scan in the region for a while: return to the base zoom
      if (currentZoom > baseZoom * (1 + AUTO_ZOOM_MIN_STEP) &&
        now - lastCandidateTime > AUTO_ZOOM_RESET_DELAY_MS &&
        zoomAnimator?.isRunning != true
      ) {
        lastCandidateTime = now
        animateZoomTo(baseZoom)
      }
      return
    }
    lastCandidateTime = now

    // A decoded barcode that will actually be emitted (fully inside the focus area when
    // filtering is on) means this zoom works: leave it alone
    if (candidates.any { (barcode, rect) -> barcode.rawValue != null && wouldBeEmitted(rect) }) return
    if (zoomAnimator?.isRunning == true || now - lastAutoZoomTime < AUTO_ZOOM_COOLDOWN_MS) return

    val target = candidates.maxByOrNull { (_, rect) -> rect.width() * rect.height() }!!.second
    val fill = max(target.width() / region.width(), target.height() / region.height())
    if (fill <= 0f) return

    val factor = when {
      // Barcode spills past the region (and is filtered out): back off
      !region.contains(target) && currentZoom > baseZoom ->
        min(AUTO_ZOOM_TARGET_FILL / fill, AUTO_ZOOM_OUT_STEP)
      fill < AUTO_ZOOM_MIN_FILL ->
        min(AUTO_ZOOM_TARGET_FILL / fill, maxZoomFactorKeepingInside(target, region, view))
      fill > AUTO_ZOOM_MAX_FILL && currentZoom > baseZoom ->
        AUTO_ZOOM_TARGET_FILL / fill
      else -> return
    }

    val upperBound = max(baseZoom, min(maxAutoZoom, zoomState.maxZoomRatio))
    val newZoom = (currentZoom * factor).coerceIn(baseZoom, upperBound)
    if (abs(newZoom - currentZoom) / currentZoom < AUTO_ZOOM_MIN_STEP) return

    lastAutoZoomTime = now
    animateZoomTo(newZoom)
  }

  /**
   * Whether a decoded barcode at [rect] (view coordinates) passes the focus area filter in
   * [processBarcodesAccordingToStrategy].
   */
  private fun wouldBeEmitted(rect: RectF): Boolean {
    if (!focusAreaEnabled) return true
    val frame = overlayView?.frameRect ?: return true
    return frame.contains(rect)
  }

  /**
   * Largest relative zoom factor that keeps [box] inside [region] (inset by a margin),
   * given that digital zoom scales around the center of the preview.
   */
  private fun maxZoomFactorKeepingInside(box: RectF, region: RectF, view: View): Float {
    val cx = view.width / 2f
    val cy = view.height / 2f
    val insetX = region.width() * AUTO_ZOOM_REGION_INSET
    val insetY = region.height() * AUTO_ZOOM_REGION_INSET
    val bounds = RectF(region.left + insetX, region.top + insetY, region.right - insetX, region.bottom - insetY)

    var limit = Float.MAX_VALUE
    if (box.left < cx) limit = min(limit, (cx - bounds.left) / (cx - box.left))
    if (box.right > cx) limit = min(limit, (bounds.right - cx) / (box.right - cx))
    if (box.top < cy) limit = min(limit, (cy - bounds.top) / (cy - box.top))
    if (box.bottom > cy) limit = min(limit, (bounds.bottom - cy) / (box.bottom - cy))
    // A limit below 1 means the box already sits at/over the edge: don't zoom in
    return max(limit, 1f)
  }


  @OptIn(ExperimentalGetImage::class)
  private fun processImage(imageProxy: ImageProxy) {
    try {
      // Skip processing if scanning is paused
      if (isScanningPaused) {
        imageProxy.close()
        return
      }

      val mediaImage = imageProxy.image
      if (mediaImage != null && previewView != null) {
        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        val transformationInfo = ImageAnalysisTransformationInfo(
          resolution = Size(imageProxy.width, imageProxy.height),
          rotationDegrees = imageProxy.imageInfo.rotationDegrees
        )

        val scanner = barcodeScanner
        scanner.process(image)
          .addOnSuccessListener { allBarcodes ->
            // Undecoded (potential) barcodes only drive auto-zoom
            evaluateAutoZoom(allBarcodes, transformationInfo)
            val barcodes = allBarcodes.filter { it.rawValue != null }

            // Process barcode detection for the main scanning logic
            if (barcodes.isNotEmpty() && !isScanningPaused) {
              val processedBarcodes = processBarcodesAccordingToStrategy(barcodes, transformationInfo)

              // Update barcode frames for processed barcodes (filtered)
              updateBarcodeFrames(processedBarcodes, transformationInfo)

              if (processedBarcodes.isNotEmpty()) {
                val currentTime = System.currentTimeMillis()
                val timeSinceLastEmission = currentTime - lastBarcodeEmissionTime

                // Debounce: Prevent rapid duplicate emissions
                // If we've emitted recently (within debounce interval), skip this emission
                // This prevents multiple alerts when pauseScanning is set but detection callbacks are still in flight
                Log.d(TAG, "📊 Debounce check: interval=${barcodeEmissionDebounceInterval}ms, timeSinceLast=${timeSinceLastEmission}ms")
                if (timeSinceLastEmission < barcodeEmissionDebounceInterval) {
                  Log.d(TAG, "⏭️ Skipping barcode emission (debounced, last emission was ${timeSinceLastEmission}ms ago, interval=${barcodeEmissionDebounceInterval}ms)")
                  return@addOnSuccessListener
                }

                lastBarcodeEmissionTime = currentTime
                Log.d(TAG, "✅ Emitting barcode (interval=${barcodeEmissionDebounceInterval}ms, timeSinceLast=${timeSinceLastEmission}ms)")

                // Create array of barcode events
                val barcodeEvents = Arguments.createArray()
                processedBarcodes.forEach { barcode ->
                  val eventData = Arguments.createMap().apply {
                    putString("data", barcode.rawValue)
                    putString("format", barcode.format.toString())
                    putDouble("timestamp", System.currentTimeMillis().toDouble())

                    // Add bounding box if available
                    barcode.boundingBox?.let { box ->
                      val boundingBoxData = Arguments.createMap().apply {
                        putDouble("left", box.left.toDouble())
                        putDouble("top", box.top.toDouble())
                        putDouble("right", box.right.toDouble())
                        putDouble("bottom", box.bottom.toDouble())
                      }
                      putMap("boundingBox", boundingBoxData)

                      // Calculate area
                      val area = (box.right - box.left) * (box.bottom - box.top)
                      putDouble("area", area.toDouble())
                    }
                  }
                  barcodeEvents.pushMap(eventData)
                }

                val ctx = reactContext
                if (ctx is ThemedReactContext) {
                  ctx.runOnUiQueueThread {
                    val eventData = Arguments.createMap().apply {
                      putArray("barcodes", barcodeEvents)
                    }
                    ctx.getJSModule(RCTEventEmitter::class.java)
                      .receiveEvent(this@ScannerView.id, "onBarcodeScanned", eventData)
                    Log.d(TAG, "✅ Barcode emitted (debounced)")
                  }
                }
              }
            } else {
              // TODO: Review this part later
              // Clear barcode frames when no barcodes are detected or scanning is paused
             // updateBarcodeFrames(emptyList(), transformationInfo)
            }
          }
          .addOnFailureListener { e ->
            // The client was replaced (auto-zoom toggled) or closed mid-frame: not a real error
            if (scanner !== barcodeScanner || cameraExecutor.isShutdown) {
              return@addOnFailureListener
            }
            // Emit onScannerError event for barcode detection failure
            emitOnScannerError(
              error = e.message ?: "Barcode detection failed",
              code = "BARCODE_DETECTION_FAILED"
            )
            Log.e(TAG, "Barcode scanning failed", e)
          }
          .addOnCompleteListener {
            imageProxy.close()
          }
      } else {
        imageProxy.close()
      }
    } catch (e: Exception) {
      Log.e(TAG, "Error processing image", e)
      imageProxy.close()
    }
  }

  // Frame setter methods
  fun setEnableFrame(enable: Boolean) {
    enableFrame = enable
    overlayView?.setEnableFrame(enable)
  }

  fun setBorderColor(color: String) {
    try {
      borderColor = color.toColorInt()
      overlayView?.setBorderColor(borderColor)
    } catch (e: Exception) {
      Log.e(TAG, "Invalid color format: $color")
    }
  }

  fun setTintColor(color: String) {
    try {
      tintColor = color.toColorInt()
      overlayView?.setTintColor(tintColor)
    } catch (e: Exception) {
      Log.e(TAG, "Invalid color format: $color")
    }
  }

  fun setFrameSize(size: FrameSize) {
    frameSize = size
    overlayView?.setFrameSize(size)
  }

  fun setShowBarcodeFramesOnlyInFrame(showOnlyInFrame: Boolean) {
    showBarcodeFramesOnlyInFrame = showOnlyInFrame
    Log.d(TAG, "Show barcode frames only in frame: $showOnlyInFrame")
  }

  // Focus area configuration methods
  fun setFocusAreaEnabled(enabled: Boolean) {
    focusAreaEnabled = enabled
    Log.d(TAG, "Focus area enabled: $enabled")
  }

  // Barcode frames configuration methods
  /**
   * Called once after all focus area props (enabled, overlay, position, size) are applied,
   * so focus is metered on the final rectangle.
   */
  fun onFocusAreaUpdated() {
    if (camera != null) {
      refocusOnScanRegion(force = true)
    }
  }

  fun setBarcodeFramesEnabled(enabled: Boolean) {
    barcodeFramesEnabled = enabled
    Log.d(TAG, "Barcode frames enabled: $enabled")
  }

  fun setBarcodeFramesColor(color: String) {
    try {
      barcodeFramesColor = color.toColorInt()
      Log.d(TAG, "Barcode frames color set: $color")
    } catch (e: Exception) {
      Log.e(TAG, "Invalid barcode frames color format: $color")
    }
  }

  fun setZoom(zoom: Float) {
    this.zoom = zoom
    zoomAnimator?.cancel()
    // Apply zoom, respecting the device's limits
    val zoomState = camera?.cameraInfo?.zoomState?.value
    val newZoom = if (zoomState != null) {
      zoom.coerceIn(zoomState.minZoomRatio, zoomState.maxZoomRatio)
    } else {
      max(zoom, 1f)
    }
    baseZoom = newZoom
    applyZoomRatio(newZoom)
    Log.d(TAG, "Setting zoom to $newZoom (requested $zoom)")
  }

  fun setAutoZoomEnabled(enabled: Boolean) {
    if (enabled == autoZoomEnabled) return
    autoZoomEnabled = enabled
    // Potential barcodes are only needed for auto-zoom: swap the client to skip that work.
    // A frame still in flight on the old client fails quietly (see processImage).
    if (!cameraExecutor.isShutdown) {
      val oldScanner = barcodeScanner
      barcodeScanner = createBarcodeScanner(withPotentialBarcodes = enabled)
      oldScanner.close()
    }
    if (!enabled && currentZoom != baseZoom && camera != null) {
      animateZoomTo(baseZoom)
    }
    Log.d(TAG, "Auto-zoom ${if (enabled) "enabled" else "disabled"}")
  }

  fun setMaxAutoZoom(value: Float) {
    maxAutoZoom = max(value, 1f)
  }

  fun setPinchToZoomEnabled(enabled: Boolean) {
    pinchToZoomEnabled = enabled
  }

  fun setTapToFocusEnabled(enabled: Boolean) {
    tapToFocusEnabled = enabled
  }

  fun setTorch(enabled: Boolean) {
    torchEnabled = enabled
    camera?.cameraControl?.enableTorch(enabled)
    Log.d(TAG, "Torch ${if (enabled) "enabled" else "disabled"}")
  }

  fun resumeScanning() {
    isScanningPaused = false
    // Reset debounce timer when resuming to allow immediate detection
    lastBarcodeEmissionTime = 0
    Log.d(TAG, "Scanning resumed")
  }

  fun pauseScanning() {
    isScanningPaused = true
    // Clear all barcode frames when pausing
    barcodeFrameManager.clearAllFrames()
    // Reset debounce timer when pausing to prevent stale emissions
    lastBarcodeEmissionTime = 0
    Log.d(TAG, "Scanning paused")
  }

  fun setBarcodeEmissionInterval(intervalSeconds: Double) {
    // Convert seconds to milliseconds, ensure non-negative
    val previousInterval = barcodeEmissionDebounceInterval
    Log.d(TAG, "📊 [ScannerView] setBarcodeEmissionInterval called with: ${intervalSeconds}s")
    barcodeEmissionDebounceInterval = max(0, (intervalSeconds * 1000).toLong())
    Log.d(TAG, "📊 ScannerView.setBarcodeEmissionInterval: ${intervalSeconds}s -> ${barcodeEmissionDebounceInterval}ms (was ${previousInterval}ms)")
    
    if (barcodeEmissionDebounceInterval == 0L) {
      Log.d(TAG, "📊 ⚠️ Debouncing DISABLED (interval = 0ms)")
    } else {
      Log.d(TAG, "📊 ✅ Debouncing ENABLED (interval = ${barcodeEmissionDebounceInterval}ms)")
    }
  }

  private fun emitOnLoadEvent(success: Boolean, error: String? = null) {
    val ctx = reactContext
    if (ctx is ThemedReactContext) {
      ctx.runOnUiQueueThread {
        val eventData = Arguments.createMap().apply {
          putBoolean("success", success)
          if (error != null) {
            putString("error", error)
          }
        }
        ctx.getJSModule(RCTEventEmitter::class.java)
          .receiveEvent(this@ScannerView.id, "onLoad", eventData)
        Log.d(TAG, "✅ onLoad event emitted: success=$success, error=$error")
      }
    }
  }

  private fun emitOnScannerError(error: String, code: String) {
    val ctx = reactContext
    if (ctx is ThemedReactContext) {
      ctx.runOnUiQueueThread {
        val eventData = Arguments.createMap().apply {
          putString("error", error)
          putString("code", code)
        }
        ctx.getJSModule(RCTEventEmitter::class.java)
          .receiveEvent(this@ScannerView.id, "onScannerError", eventData)
        Log.d(TAG, "✅ onScannerError event emitted: code=$code, error=$error")
      }
    }
  }

  private fun emitOnZoomChange(zoom: Float) {
    val ctx = reactContext
    if (ctx is ThemedReactContext) {
      ctx.runOnUiQueueThread {
        val eventData = Arguments.createMap().apply {
          putDouble("zoom", zoom.toDouble())
        }
        ctx.getJSModule(RCTEventEmitter::class.java)
          .receiveEvent(this@ScannerView.id, "onZoomChange", eventData)
      }
    }
  }

  fun setBarcodeScanStrategy(strategy: String) {
    barcodeScanStrategy = strategy
    Log.d(TAG, "Barcode scan strategy set to: $strategy")
  }

  fun setPosition(x: Float, y: Float) {
    positionX = x.coerceIn(0f, 100f) // Clamp to 0-100 range
    positionY = y.coerceIn(0f, 100f) // Clamp to 0-100 range
    overlayView?.setPosition(positionX, positionY)
    Log.d(TAG, "Focus area position set to: x=$positionX%, y=$positionY%")
  }

  fun setKeepScreenOnEnabled(keepOn: Boolean) {
    updateKeepScreenOn(keepOn)
  }

  private fun hasCameraPermission(): Boolean {
    return context.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
  }

  private fun updateBarcodeFrames(
    barcodes: List<Barcode>,
    transformationInfo: ImageAnalysisTransformationInfo
  ) {
    // Only update barcode frames if they are enabled
    if (!barcodeFramesEnabled) {
      return
    }

    val barcodeFrames = mutableMapOf<String, RectF>()

    barcodes.forEach { barcode ->
      val barcodeValue = barcode.rawValue ?: return@forEach
      val boundingBox = barcode.boundingBox ?: return@forEach

      val transformedRect = transformBarcodeBoundingBox(
        boundingBox,
        transformationInfo,
        previewView!!
      )

      // If showBarcodeFramesOnlyInFrame is true, only include frames within the overlay frame
      if (showBarcodeFramesOnlyInFrame && enableFrame) {
        val frame = overlayView?.frameRect
        if (frame != null && frame.contains(transformedRect)) {
          barcodeFrames[barcodeValue] = transformedRect
        }
      } else {
        // Show all barcode frames
        barcodeFrames[barcodeValue] = transformedRect
      }
    }

    // Update frames using the manager
    barcodeFrameManager.updateBarcodeFrames(barcodeFrames)
  }

  private fun processBarcodesAccordingToStrategy(
    barcodes: List<Barcode>,
    transformationInfo: ImageAnalysisTransformationInfo
  ): List<Barcode> {
    if (barcodes.isEmpty()) return emptyList()

    // Filter barcodes based on focus area if enabled
    val filteredBarcodes = if (focusAreaEnabled) {
      val frame = overlayView?.frameRect
      if (frame != null) {
        barcodes.filter { barcode ->
          barcode.boundingBox?.let { box ->
            val transformedBox = transformBarcodeBoundingBox(box, transformationInfo, previewView!!)
            frame.contains(transformedBox)
          } ?: false
        }
      } else {
        barcodes
      }
    } else {
      barcodes
    }

    if (filteredBarcodes.isEmpty()) return emptyList()

    // Apply strategy
    return when (barcodeScanStrategy) {
      "ONE" -> {
        listOf(filteredBarcodes[0])
      }
      "BIGGEST" -> {
        val barcodeWithArea = filteredBarcodes.mapNotNull { barcode ->
          barcode.boundingBox?.let { box ->
            val area = (box.right - box.left) * (box.bottom - box.top)
            barcode to area
          }
        }
        if (barcodeWithArea.isNotEmpty()) {
          val biggest = barcodeWithArea.maxByOrNull { it.second }
          listOf(biggest!!.first)
        } else {
          listOf(filteredBarcodes[0])
        }
      }
      "SORT_BY_BIGGEST" -> {
        val barcodeWithArea = filteredBarcodes.mapNotNull { barcode ->
          barcode.boundingBox?.let { box ->
            val area = (box.right - box.left) * (box.bottom - box.top)
            barcode to area
          }
        }
        if (barcodeWithArea.isNotEmpty()) {
          barcodeWithArea.sortedByDescending { it.second }.map { it.first }
        } else {
          filteredBarcodes
        }
      }
      "ALL" -> filteredBarcodes
      else -> filteredBarcodes // Default to ALL
    }
  }
}

private data class ImageAnalysisTransformationInfo(
  val resolution: Size,
  val rotationDegrees: Int
)

private fun transformBarcodeBoundingBox(
  barcodeBoundingBox: Rect,
  imageAnalysisInfo: ImageAnalysisTransformationInfo,
  previewView: View
): RectF {
  // Get image analysis resolution and rotation
  val imageWidth = imageAnalysisInfo.resolution.width
  val imageHeight = imageAnalysisInfo.resolution.height
  val imageRotation = imageAnalysisInfo.rotationDegrees

  // Adjust for rotation
  val (rotatedWidth, rotatedHeight) = if (imageRotation == 90 || imageRotation == 270) {
    imageHeight to imageWidth
  } else {
    imageWidth to imageHeight
  }

  // Get preview view dimensions
  val viewWidth = previewView.width
  val viewHeight = previewView.height

  // Calculate scale factors
  val scaleX = viewWidth.toFloat() / rotatedWidth
  val scaleY = viewHeight.toFloat() / rotatedHeight
  val scale = maxOf(scaleX, scaleY) // For FILL_CENTER

  // Calculate offsets
  val offsetX = (viewWidth - rotatedWidth * scale) / 2
  val offsetY = (viewHeight - rotatedHeight * scale) / 2

  // Transform the bounding box
  val transformedRect = RectF(barcodeBoundingBox)
  transformedRect.left = transformedRect.left * scale + offsetX
  transformedRect.top = transformedRect.top * scale + offsetY
  transformedRect.right = transformedRect.right * scale + offsetX
  transformedRect.bottom = transformedRect.bottom * scale + offsetY

  return transformedRect
}
