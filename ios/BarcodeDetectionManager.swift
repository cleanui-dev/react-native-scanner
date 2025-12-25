//
//  BarcodeDetectionManager.swift
//  react-native-scanner
//
//  Manages barcode detection using Vision framework
//

import Foundation
import Vision
import AVFoundation

/// Manages barcode detection using Vision framework
class BarcodeDetectionManager: NSObject, BarcodeScannerProtocol {
    
    // MARK: - Public Properties
    
    /// Delegate for detection events
    weak var delegate: BarcodeDetectionDelegate?
    
    // MARK: - Private Properties
    
    /// Supported barcode symbologies
    private var supportedSymbologies: [VNBarcodeSymbology]
    
    /// Scan strategy
    private var scanStrategy: BarcodeScanStrategy
    
    /// Whether scanning is paused
    private var scanningPaused: Bool
    
    /// Background queue for detection
    private let detectionQueue: DispatchQueue
    
    // MARK: - Initialization
    
    override init() {
        // Default: all supported formats
        self.supportedSymbologies = [
            .qr, .code128, .code39, .ean13, .ean8,
            .upce, .pdf417, .aztec, .dataMatrix, .itf14
        ]
        self.scanStrategy = .defaultStrategy
        self.scanningPaused = false
        self.detectionQueue = DispatchQueue(label: "com.scanner.detection")
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Detect barcodes in a sample buffer
    /// - Parameter sampleBuffer: The sample buffer to analyze
    func detectBarcodes(in sampleBuffer: CMSampleBuffer) {
        guard !scanningPaused else { return }
        
        guard let pixelBuffer = getPixelBuffer(from: sampleBuffer) else {
            return
        }
        
        let request = createDetectionRequest()
        let orientation = getImageOrientation(from: sampleBuffer)
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                           orientation: orientation,
                                           options: [:])
        
        detectionQueue.async { [weak self] in
            do {
                try handler.perform([request])
            } catch {
                print("[BarcodeDetectionManager] Detection failed: \(error)")
                DispatchQueue.main.async {
                    self?.delegate?.barcodeDetectionManager(self!, didFailWith: error)
                }
            }
        }
    }
    
    /// Detect barcodes in a CMSampleBuffer with completion
    /// - Parameters:
    ///   - sampleBuffer: The sample buffer to analyze
    ///   - completion: Completion handler with observations
    func detectBarcodes(in sampleBuffer: CMSampleBuffer,
                       completion: @escaping ([VNBarcodeObservation]) -> Void) {
        guard !scanningPaused else {
            completion([])
            return
        }
        
        guard let pixelBuffer = getPixelBuffer(from: sampleBuffer) else {
            completion([])
            return
        }
        
        let request = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("[BarcodeDetectionManager] Detection error: \(error)")
                completion([])
                return
            }
            
            guard let results = request.results as? [VNBarcodeObservation] else {
                completion([])
                return
            }
            
            completion(results)
        }
        
        request.symbologies = supportedSymbologies
        
        let orientation = getImageOrientation(from: sampleBuffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                           orientation: orientation,
                                           options: [:])
        
        detectionQueue.async {
            do {
                try handler.perform([request])
            } catch {
                print("[BarcodeDetectionManager] Detection failed: \(error)")
                completion([])
            }
        }
    }
    
    // MARK: - BarcodeScannerProtocol Methods
    
    /// Pause barcode scanning
    func pauseScanning() {
        scanningPaused = true
        print("[BarcodeDetectionManager] Scanning paused")
    }
    
    /// Resume barcode scanning
    func resumeScanning() {
        scanningPaused = false
        print("[BarcodeDetectionManager] Scanning resumed")
    }
    
    /// Check if scanning is paused
    /// - Returns: True if scanning is paused
    func isScanningPaused() -> Bool {
        // Implementation: Return paused state
        return scanningPaused
    }
    
    /// Set the barcode formats to detect
    /// - Parameter formats: Array of barcode formats
    func setBarcodeFormats(_ formats: [BarcodeFormat]) {
        if formats.isEmpty {
            // If empty, use all supported formats
            supportedSymbologies = [
                .qr, .code128, .code39, .ean13, .ean8,
                .upce, .pdf417, .aztec, .dataMatrix, .itf14
            ]
        } else {
            supportedSymbologies = formats.map { $0.visionSymbology }
        }
        print("[BarcodeDetectionManager] Barcode formats updated: \(supportedSymbologies)")
    }
    
    /// Set the scan strategy
    /// - Parameter strategy: The scan strategy to use
    func setScanStrategy(_ strategy: BarcodeScanStrategy) {
        scanStrategy = strategy
        print("[BarcodeDetectionManager] Scan strategy set to: \(strategy.rawValue)")
    }
    
    // MARK: - Private Methods
    
    /// Create a barcode detection request
    /// - Returns: Configured VNDetectBarcodesRequest
    private func createDetectionRequest() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest { [weak self] request, error in
            self?.handleDetectionResults(request: request, error: error)
        }
        
        request.symbologies = supportedSymbologies
        
        return request
    }
    
    /// Process detection results
    /// - Parameters:
    ///   - request: The completed request
    ///   - error: Any error that occurred
    private func handleDetectionResults(request: VNRequest, error: Error?) {
        if let error = error {
            print("[BarcodeDetectionManager] Detection error: \(error)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.barcodeDetectionManager(self, didFailWith: error)
            }
            return
        }
        
        guard let results = request.results as? [VNBarcodeObservation] else {
            return
        }
        
        // Filter out barcodes without valid payload
        let validBarcodes = results.filter { $0.payloadStringValue != nil }
        
        if !validBarcodes.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.barcodeDetectionManager(self, didDetect: validBarcodes)
            }
        }
    }
    
    /// Get pixel buffer from sample buffer
    /// - Parameter sampleBuffer: The sample buffer
    /// - Returns: Pixel buffer or nil
    private func getPixelBuffer(from sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        return CMSampleBufferGetImageBuffer(sampleBuffer)
    }
    
    /// Get image orientation from sample buffer
    /// - Parameter sampleBuffer: The sample buffer
    /// - Returns: CGImagePropertyOrientation
    private func getImageOrientation(from sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        // For most cases, .up works well
        // In production, you might want to account for device orientation
        return .up
    }
}

