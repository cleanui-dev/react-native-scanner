# iOS Scanner Implementation - Interface Summary

## Overview
This document provides a complete overview of all Swift interfaces defined for the iOS barcode scanner implementation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 React Native (JavaScript)                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│           ScannerView.mm (Objective-C++ Bridge)              │
│         - Fabric Props Handling                              │
│         - Event Emission                                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│           ScannerViewImpl.swift (Main Controller)            │
│         - Coordinates all components                         │
│         - Implements delegate patterns                       │
└─────┬──────────┬──────────┬──────────┬──────────┬──────────┘
      │          │          │          │          │
      ▼          ▼          ▼          ▼          ▼
┌─────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│ Camera  │ │Barcode │ │ Focus  │ │Barcode │ │Coord.  │
│ Manager │ │Detect. │ │ Area   │ │ Frame  │ │ Trans. │
│         │ │Manager │ │ Overlay│ │ Mgr    │ │        │
└─────────┘ └────────┘ └────────┘ └────────┘ └────────┘
```

## File Structure

### Core Files
1. **Models.swift** - Data structures and enums
2. **Protocols.swift** - Protocol definitions
3. **ScannerViewImpl.swift** - Main scanner view
4. **CameraManager.swift** - AVFoundation camera management
5. **BarcodeDetectionManager.swift** - Vision framework detection
6. **FocusAreaOverlayView.swift** - Focus area visualization
7. **BarcodeFrameOverlayView.swift** - Barcode frame visualization
8. **BarcodeFrameManager.swift** - Frame lifecycle management
9. **CoordinateTransformer.swift** - Coordinate transformation

### Bridge Files
- **ScannerView.h** - Objective-C header
- **ScannerView.mm** - Objective-C++ implementation (Fabric bridge)
- **react-native-scanner-Bridging-Header.h** - Swift/Objective-C bridging

## Data Models

### BarcodeFormat (Enum)
Supported barcode formats mapped to Vision framework symbologies:
- QR_CODE → .qr
- CODE_128 → .code128
- CODE_39 → .code39
- EAN_13 → .ean13
- EAN_8 → .ean8
- UPC_A → .upce
- UPC_E → .upce
- DATA_MATRIX → .dataMatrix
- PDF_417 → .pdf417
- AZTEC → .aztec
- ITF → .itf14

### BarcodeScanStrategy (Enum)
- ONE - Process only first barcode
- ALL - Process all barcodes
- BIGGEST - Process largest barcode by area
- SORT_BY_BIGGEST - Process all, sorted by size

### FrameSize (Enum)
- square(size: CGFloat)
- rectangle(width: CGFloat, height: CGFloat)

### FocusAreaConfig (Struct)
```swift
struct FocusAreaConfig {
    var enabled: Bool               // Filter scanning to focus area
    var showOverlay: Bool           // Show visual overlay
    var size: FrameSize            // Size of focus area
    var borderColor: UIColor       // Border color
    var tintColor: UIColor         // Semi-transparent overlay color
    var position: CGPoint          // Position (0-100 percentage)
}
```

### BarcodeFramesConfig (Struct)
```swift
struct BarcodeFramesConfig {
    var enabled: Bool              // Show barcode frames
    var color: UIColor            // Frame color
    var onlyInFocusArea: Bool     // Only show in focus area
}
```

### BarcodeDetectionResult (Struct)
```swift
struct BarcodeDetectionResult {
    let data: String              // Barcode data
    let format: String           // Barcode format
    let timestamp: TimeInterval  // Detection time (ms)
    let boundingBox: CGRect?     // Bounding box
    let area: CGFloat?           // Area
}
```

## Protocols

### ScannerViewDelegate (Objective-C)
```swift
@objc protocol ScannerViewDelegate: AnyObject {
    func scannerDidDetectBarcodes(_ barcodes: [[String: Any]])
    func scannerDidEncounterError(_ error: [String: Any])
    func scannerDidLoad(_ info: [String: Any])
}
```

### CameraManagerDelegate
```swift
protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManagerDidFail(_ manager: CameraManager, error: Error)
    func cameraManagerDidStart(_ manager: CameraManager)
}
```

### BarcodeDetectionDelegate
```swift
protocol BarcodeDetectionDelegate: AnyObject {
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager, 
                                didDetect observations: [VNBarcodeObservation])
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager, 
                                didFailWith error: Error)
}
```

### BarcodeFrameManagerDelegate
```swift
protocol BarcodeFrameManagerDelegate: AnyObject {
    func barcodeFrameManager(_ manager: BarcodeFrameManager, 
                           didUpdateFrames frames: [CGRect])
}
```

### CameraControlProtocol
```swift
protocol CameraControlProtocol {
    func startCamera()
    func stopCamera()
    func setTorch(enabled: Bool)
    func setZoom(level: CGFloat)
    func isTorchAvailable() -> Bool
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer?
}
```

### BarcodeScannerProtocol
```swift
protocol BarcodeScannerProtocol {
    func pauseScanning()
    func resumeScanning()
    func isScanningPaused() -> Bool
    func setBarcodeFormats(_ formats: [BarcodeFormat])
    func setScanStrategy(_ strategy: BarcodeScanStrategy)
}
```

## Main Classes

### ScannerViewImpl
**Purpose**: Main coordinator, manages all components and React Native integration

**Public Methods** (called from Objective-C):
- `setBarcodeTypes(_ formats: [String])`
- `configureFocusArea(_ config: [String: Any])`
- `configureBarcodeFrames(_ config: [String: Any])`
- `setTorchEnabled(_ enabled: Bool)`
- `setZoomLevel(_ zoom: Double)`
- `setPauseScanning(_ paused: Bool)`
- `setBarcodeScanStrategy(_ strategy: String)`
- `setKeepScreenOn(_ keepOn: Bool)`

**Delegates**: CameraManagerDelegate, BarcodeDetectionDelegate, BarcodeFrameManagerDelegate

### CameraManager
**Purpose**: Manages AVCaptureSession, camera input/output

**Key Responsibilities**:
- Start/stop camera
- Configure camera input (back camera)
- Setup video data output
- Control torch and zoom
- Provide preview layer
- Forward frames to delegate

**Implements**: CameraControlProtocol, AVCaptureVideoDataOutputSampleBufferDelegate

### BarcodeDetectionManager
**Purpose**: Detects barcodes using Vision framework

**Key Responsibilities**:
- Create and execute VNDetectBarcodesRequest
- Filter by supported formats
- Handle detection results
- Forward observations to delegate

**Implements**: BarcodeScannerProtocol

### FocusAreaOverlayView
**Purpose**: Draws focus area overlay with semi-transparent tint

**Key Responsibilities**:
- Draw semi-transparent overlay covering entire view
- Clear rectangular focus area (transparent)
- Draw border around focus area
- Calculate frame position based on percentage
- Check if points/rects are within focus area

**Implements**: FocusAreaProtocol, UIView drawing

### BarcodeFrameOverlayView
**Purpose**: Draws rectangles around detected barcodes

**Key Responsibilities**:
- Draw rectangles for each detected barcode
- Update display when frames change
- Use configurable color and stroke width

**Implements**: BarcodeFrameDisplayProtocol, UIView drawing

### BarcodeFrameManager
**Purpose**: Manages barcode frame lifecycle with timeout

**Key Responsibilities**:
- Store active barcode frames with timestamps
- Remove stale frames after timeout (1 second)
- Schedule cleanup timer
- Notify delegate when frames change
- Thread-safe frame management

**Implements**: Frame lifecycle management

### CoordinateTransformer
**Purpose**: Transform coordinates between Vision and View spaces

**Key Responsibilities**:
- Vision coordinates: normalized (0-1), bottom-left origin
- View coordinates: points, top-left origin
- Account for AVLayerVideoGravity
- Flip Y-axis
- Scale coordinates

**Implements**: CoordinateTransformationProtocol (static methods)

## Data Flow

### Barcode Detection Flow
```
1. CameraManager captures frame (CMSampleBuffer)
   ↓
2. Forward to ScannerViewImpl (if not paused)
   ↓
3. ScannerViewImpl → BarcodeDetectionManager.detectBarcodes()
   ↓
4. Vision framework processes frame → VNBarcodeObservation[]
   ↓
5. Back to ScannerViewImpl via delegate
   ↓
6. Filter by focus area (if enabled)
   ↓
7. Apply scan strategy (ONE, ALL, BIGGEST, SORT_BY_BIGGEST)
   ↓
8. Transform coordinates to view space
   ↓
9. Update BarcodeFrameManager (if frames enabled)
   ↓
10. Emit to React Native via delegate
```

### Frame Display Flow
```
1. Barcode detected with bounding box
   ↓
2. Transform coordinates (Vision → View)
   ↓
3. BarcodeFrameManager.updateBarcodeFrames()
   ↓
4. Manager stores with timestamp
   ↓
5. Manager notifies delegate
   ↓
6. BarcodeFrameOverlayView.setBarcodeBoxes()
   ↓
7. View calls setNeedsDisplay()
   ↓
8. draw() renders rectangles
   ↓
9. After timeout, cleanup removes stale frames
```

## Props Mapping (React Native → Swift)

| React Native Prop | Swift Method | Swift Property |
|-------------------|--------------|----------------|
| `barcodeTypes` | `setBarcodeTypes()` | `supportedSymbologies` |
| `focusArea` | `configureFocusArea()` | `focusAreaConfig` |
| `barcodeFrames` | `configureBarcodeFrames()` | `barcodeFramesConfig` |
| `torch` | `setTorchEnabled()` | Camera torch mode |
| `zoom` | `setZoomLevel()` | Camera zoom factor |
| `pauseScanning` | `setPauseScanning()` | `isPaused` |
| `barcodeScanStrategy` | `setBarcodeScanStrategy()` | `scanStrategy` |
| `keepScreenOn` | `setKeepScreenOn()` | `UIApplication.isIdleTimerDisabled` |

## Events Emitted to React Native

### onBarcodeScanned
```javascript
{
  nativeEvent: {
    barcodes: [
      {
        data: string,
        format: string,
        timestamp: number,
        boundingBox: { left, top, right, bottom },
        area: number
      }
    ]
  }
}
```

### onScannerError
```javascript
{
  nativeEvent: {
    error: string,
    code: string
  }
}
```

### onLoad
```javascript
{
  nativeEvent: {
    success: boolean,
    error?: string
  }
}
```

## Coordinate Transformation Details

### Challenge
- **Vision Framework**: Normalized (0-1), bottom-left origin
- **UIKit**: Points, top-left origin
- **Preview Layer**: May have scaling/cropping based on videoGravity

### Solution
```
1. Vision Rect (normalized, bottom-left)
   ↓
2. Denormalize to view size (multiply by width/height)
   ↓
3. Flip Y-axis (subtract from height)
   ↓
4. Account for preview layer transformation
   ↓
5. View Rect (points, top-left)
```

## Implementation Status

✅ **COMPLETED**: All interface definitions
⏳ **PENDING**: Implementation code for each method
⏳ **PENDING**: Testing and debugging
⏳ **PENDING**: Integration with React Native Fabric bridge

## Next Steps

1. Implement CameraManager (camera setup and control)
2. Implement BarcodeDetectionManager (Vision framework)
3. Implement CoordinateTransformer (coordinate math)
4. Implement FocusAreaOverlayView (drawing)
5. Implement BarcodeFrameOverlayView (drawing)
6. Implement BarcodeFrameManager (lifecycle)
7. Implement ScannerViewImpl (main coordinator)
8. Update ScannerView.mm (Objective-C bridge)
9. Test on physical device
10. Debug and refine

## Notes

- All interfaces are defined with clear responsibilities
- Protocols enforce contracts between components
- Models provide type-safe data structures
- Coordinate transformation is isolated in dedicated class
- Frame lifecycle management prevents flickering
- Thread-safe implementation where needed
- Main thread for UI updates
- Background threads for camera/detection

