//
//  BarcodeFrameManager.swift
//  react-native-scanner
//
//  Manages barcode frame lifecycle with timeout
//

import Foundation
import CoreGraphics

/// Manages barcode frames with automatic timeout and cleanup
class BarcodeFrameManager {
    
    // MARK: - Public Properties
    
    /// Delegate for frame change notifications
    weak var delegate: BarcodeFrameManagerDelegate?
    
    /// Callback for frame changes
    var onFramesChanged: (([CGRect]) -> Void)?
    
    // MARK: - Private Properties
    
    /// Active barcode frames mapped by barcode data
    private var activeFrames: [String: BarcodeFrame] = [:]
    
    /// Timeout duration for frames (seconds)
    private let frameTimeout: TimeInterval
    
    /// Timer for cleanup
    private var cleanupTimer: Timer?
    
    /// Queue for thread-safe access
    private let queue: DispatchQueue
    
    // MARK: - Initialization
    
    init(frameTimeout: TimeInterval = 1.0) {
        self.frameTimeout = frameTimeout
        self.queue = DispatchQueue(label: "com.scanner.framemanager", attributes: .concurrent)
    }
    
    // MARK: - Public Methods
    
    /// Update barcode frames with new detections
    /// - Parameter frames: Dictionary mapping barcode data to rectangles
    func updateBarcodeFrames(_ frames: [String: CGRect]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let currentKeys = Set(frames.keys)
            
            // Update or add frames with current timestamp
            for (key, rect) in frames {
                self.activeFrames[key] = BarcodeFrame(rect: rect, lastSeenTime: now)
            }
            
            // Remove frames not in current detection
            self.activeFrames = self.activeFrames.filter { currentKeys.contains($0.key) }
            
            // Schedule cleanup if we have frames
            if !self.activeFrames.isEmpty {
                DispatchQueue.main.async {
                    self.scheduleCleanup()
                }
            }
            
            // Notify observers
            self.notifyFramesChanged()
        }
    }
    
    /// Get current active frames for display
    /// - Returns: Array of active frame rectangles
    func getActiveFrames() -> [CGRect] {
        return queue.sync {
            return activeFrames.values.map { $0.rect }
        }
    }
    
    /// Clear all barcode frames immediately
    func clearAllFrames() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let hadFrames = !self.activeFrames.isEmpty
            self.activeFrames.removeAll()
            
            DispatchQueue.main.async {
                self.cleanupTimer?.invalidate()
                self.cleanupTimer = nil
                
                if hadFrames {
                    self.notifyFramesChanged()
                }
            }
        }
    }
    
    /// Shutdown the manager and cleanup resources
    func shutdown() {
        clearAllFrames()
        print("[BarcodeFrameManager] Shutdown")
    }
    
    // MARK: - Private Methods
    
    /// Schedule cleanup of stale frames
    private func scheduleCleanup() {
        // Cancel existing timer
        cleanupTimer?.invalidate()
        
        // Schedule new timer
        cleanupTimer = Timer.scheduledTimer(
            timeInterval: frameTimeout,
            target: self,
            selector: #selector(cleanupStaleFrames),
            userInfo: nil,
            repeats: false
        )
    }
    
    /// Clean up stale frames
    @objc private func cleanupStaleFrames() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let countBefore = self.activeFrames.count
            
            // Remove frames older than timeout
            self.activeFrames = self.activeFrames.filter { _, frame in
                now.timeIntervalSince(frame.lastSeenTime) < self.frameTimeout
            }
            
            let framesRemoved = countBefore - self.activeFrames.count
            
            if framesRemoved > 0 {
                print("[BarcodeFrameManager] Removed \(framesRemoved) stale frame(s)")
                self.notifyFramesChanged()
            }
            
            // Reschedule if frames remain
            if !self.activeFrames.isEmpty {
                DispatchQueue.main.async {
                    self.scheduleCleanup()
                }
            } else {
                print("[BarcodeFrameManager] No more frames to monitor")
            }
        }
    }
    
    /// Notify observers of frame changes
    private func notifyFramesChanged() {
        let currentFrames = activeFrames.values.map { $0.rect }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Call delegate
            self.delegate?.barcodeFrameManager(self, didUpdateFrames: currentFrames)
            
            // Call callback
            self.onFramesChanged?(currentFrames)
        }
    }
    
    deinit {
        // Implementation: Cleanup timer
        cleanupTimer?.invalidate()
    }
}

