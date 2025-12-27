export { BarcodeFormat, BarcodeScanStrategy } from './types';
export type {
  FrameSize,
  FocusAreaConfig,
  BarcodeFramesConfig,
  BarcodeScannedEventPayload,
  ScannerErrorEventPayload,
  OnLoadEventPayload,
  DeviceCameraInfo,
  CurrentCameraInfo,
  CameraInfo,
  CameraFacing,
} from './types';

// Export the camera info hook
export { useCameraInfo } from './hooks/useCameraInfo';
export type { UseCameraInfoReturn } from './hooks/useCameraInfo';

// Re-export the native component

export { default as ScannerView } from './ScannerViewNativeComponent';
export * from './ScannerViewNativeComponent';
