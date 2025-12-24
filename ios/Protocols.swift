//
//  Protocols.swift
//  react-native-scanner
//
//  Protocol definitions for scanner components
//

import Foundation
import AVFoundation
import Vision

// MARK: - Scanner View Delegate

/// Delegate protocol for scanner events to be sent to React Native
@objc protocol ScannerViewDelegate: AnyObject {
    /// Called when barcodes are detected
    /// - Parameter barcodes: Array of detected barcode dictionaries
    func scannerDidDetectBarcodes(_ barcodes: [[String: Any]])
    
    /// Called when an error occurs
    /// - Parameter error: Error information dictionary
    func scannerDidEncounterError(_ error: [String: Any])
    
    /// Called when the scanner is loaded and ready
    /// - Parameter info: Load information dictionary
    func scannerDidLoad(_ info: [String: Any])
}

// MARK: - Camera Manager Delegate

/// Delegate protocol for camera events
protocol CameraManagerDelegate: AnyObject {
    /// Called when a new video frame is captured
    /// - Parameters:
    ///   - manager: The camera manager
    ///   - sampleBuffer: The captured sample buffer
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    
    /// Called when camera initialization fails
    /// - Parameters:
    ///   - manager: The camera manager
    ///   - error: The error that occurred
    func cameraManagerDidFail(_ manager: CameraManager, error: Error)
    
    /// Called when camera successfully starts
    /// - Parameter manager: The camera manager
    func cameraManagerDidStart(_ manager: CameraManager)
}

// MARK: - Barcode Detection Delegate

/// Delegate protocol for barcode detection events
protocol BarcodeDetectionDelegate: AnyObject {
    /// Called when barcodes are detected in a frame
    /// - Parameters:
    ///   - manager: The detection manager
    ///   - observations: Array of barcode observations
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager, 
                                 didDetect observations: [VNBarcodeObservation])
    
    /// Called when barcode detection fails
    /// - Parameters:
    ///   - manager: The detection manager
    ///   - error: The error that occurred
    func barcodeDetectionManager(_ manager: BarcodeDetectionManager, 
                                 didFailWith error: Error)
}

// MARK: - Barcode Frame Manager Delegate

/// Delegate protocol for barcode frame changes
protocol BarcodeFrameManagerDelegate: AnyObject {
    /// Called when the active barcode frames change
    /// - Parameters:
    ///   - manager: The frame manager
    ///   - frames: Array of active frame rectangles
    func barcodeFrameManager(_ manager: BarcodeFrameManager, 
                            didUpdateFrames frames: [CGRect])
}

// MARK: - Camera Control Protocol

/// Protocol for camera control operations
protocol CameraControlProtocol {
    /// Start the camera session
    func startCamera()
    
    /// Stop the camera session
    func stopCamera()
    
    /// Set torch/flashlight state
    /// - Parameter enabled: Whether torch should be enabled
    func setTorch(enabled: Bool)
    
    /// Set zoom level
    /// - Parameter level: The zoom level (clamped to device limits)
    func setZoom(level: CGFloat)
    
    /// Check if torch is available
    /// - Returns: True if torch is available
    func isTorchAvailable() -> Bool
    
    /// Get the preview layer for displaying camera feed
    /// - Returns: The AVCaptureVideoPreviewLayer
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer?
}

// MARK: - Barcode Scanner Protocol

/// Protocol for barcode scanning operations
protocol BarcodeScannerProtocol {
    /// Pause barcode scanning
    func pauseScanning()
    
    /// Resume barcode scanning
    func resumeScanning()
    
    /// Check if scanning is paused
    /// - Returns: True if scanning is paused
    func isScanningPaused() -> Bool
    
    /// Set the barcode formats to detect
    /// - Parameter formats: Array of barcode formats
    func setBarcodeFormats(_ formats: [BarcodeFormat])
    
    /// Set the scan strategy
    /// - Parameter strategy: The scan strategy to use
    func setScanStrategy(_ strategy: BarcodeScanStrategy)
}

// MARK: - Focus Area Protocol

/// Protocol for focus area operations
protocol FocusAreaProtocol {
    /// Update focus area configuration
    /// - Parameter config: The new configuration
    func updateFocusArea(config: FocusAreaConfig)
    
    /// Get the current focus area frame in view coordinates
    /// - Returns: The focus area rectangle
    func getFocusAreaFrame() -> CGRect?
    
    /// Check if a point is within the focus area
    /// - Parameter point: The point to check
    /// - Returns: True if the point is within the focus area
    func isPointInFocusArea(_ point: CGPoint) -> Bool
    
    /// Check if a rectangle intersects or is contained in the focus area
    /// - Parameter rect: The rectangle to check
    /// - Returns: True if the rectangle intersects or is contained
    func isRectInFocusArea(_ rect: CGRect) -> Bool
}

// MARK: - Barcode Frame Display Protocol

/// Protocol for displaying barcode frames
protocol BarcodeFrameDisplayProtocol {
    /// Update the barcode frames configuration
    /// - Parameter config: The new configuration
    func updateBarcodeFrames(config: BarcodeFramesConfig)
    
    /// Set the barcode boxes to display
    /// - Parameter boxes: Array of rectangles to display
    func setBarcodeBoxes(_ boxes: [CGRect])
    
    /// Clear all barcode boxes
    func clearBarcodeBoxes()
}

// MARK: - Coordinate Transformation Protocol

/// Protocol for coordinate transformation operations
protocol CoordinateTransformationProtocol {
    /// Transform Vision framework coordinates to view coordinates
    /// - Parameters:
    ///   - visionRect: Rectangle in Vision coordinate space (normalized, bottom-left origin)
    ///   - viewSize: The size of the view
    ///   - previewLayer: The preview layer for additional transformation
    /// - Returns: Rectangle in view coordinate space
    static func transformVisionRectToViewRect(_ visionRect: CGRect,
                                             viewSize: CGSize,
                                             previewLayer: AVCaptureVideoPreviewLayer?) -> CGRect
    
    /// Transform view coordinates to Vision framework coordinates
    /// - Parameters:
    ///   - viewRect: Rectangle in view coordinate space
    ///   - viewSize: The size of the view
    ///   - previewLayer: The preview layer for additional transformation
    /// - Returns: Rectangle in Vision coordinate space
    static func transformViewRectToVisionRect(_ viewRect: CGRect,
                                             viewSize: CGSize,
                                             previewLayer: AVCaptureVideoPreviewLayer?) -> CGRect
}

