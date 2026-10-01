import {
  codegenNativeComponent,
  type CodegenTypes,
  type HostComponent,
  type ViewProps,
} from 'react-native';

// Event payload types for better TypeScript inference
export interface BarcodeScannedEventPayload {
  barcodes: {
    data: string;
    format: string;
    timestamp: CodegenTypes.Double;
    boundingBox?: {
      left: CodegenTypes.Double;
      top: CodegenTypes.Double;
      right: CodegenTypes.Double;
      bottom: CodegenTypes.Double;
    };
    area?: CodegenTypes.Double;
  }[];
}

export interface ScannerErrorEventPayload {
  error: string;
  code: string;
}

export interface OnLoadEventPayload {
  success: boolean;
  error?: string;
}

// Event types for use in handlers, taken from the props so they always match
// what ScannerView passes (react-native's strict API adds fields to these events)
type EventOf<Handler extends ((event: never) => unknown) | undefined> =
  Parameters<NonNullable<Handler>>[0];
export type BarcodeScannedEvent = EventOf<NativeProps['onBarcodeScanned']>;
export type ScannerErrorEvent = EventOf<NativeProps['onScannerError']>;
export type OnLoadEvent = EventOf<NativeProps['onLoad']>;

// Nested object types for better codegen compatibility
export interface FocusAreaSize {
  width: CodegenTypes.Double;
  height: CodegenTypes.Double;
}

export interface FocusAreaPosition {
  x: CodegenTypes.Double; // 0-100
  y: CodegenTypes.Double; // 0-100
}

export interface FocusAreaConfig {
  enabled?: boolean;
  showOverlay?: boolean;
  borderColor?: string;
  tintColor?: string;
  // NOTE: Codegen does not support mixed types (number OR object), so we always pass {width,height}.
  size?: FocusAreaSize;
  position?: FocusAreaPosition;
}

export interface BarcodeFramesConfig {
  enabled?: boolean;
  color?: string;
  onlyInFocusArea?: boolean;
}

export interface BoundingBox {
  left: CodegenTypes.Double;
  top: CodegenTypes.Double;
  right: CodegenTypes.Double;
  bottom: CodegenTypes.Double;
}

export interface BarcodeData {
  data: string;
  format: string;
  timestamp: CodegenTypes.Double;
  boundingBox?: BoundingBox;
  area?: CodegenTypes.Double;
}

export interface NativeProps extends ViewProps {
  barcodeTypes?: string[];

  /**
   * Focus area configuration (Android: drives overlay + optional filtering).
   * - `showOverlay` controls whether the scanning region is drawn.
   * - `enabled` controls whether scanning is restricted to that region.
   */
  focusArea?: FocusAreaConfig;

  /**
   * Barcode frames configuration (draw rectangles around detected barcodes).
   */
  barcodeFrames?: BarcodeFramesConfig;

  torch?: boolean;
  zoom?: CodegenTypes.Double;
  pauseScanning?: boolean;

  barcodeScanStrategy?: string;
  keepScreenOn?: boolean;

  /**
   * Minimum interval (in seconds) between barcode emission events.
   * Prevents rapid duplicate detections. Set to 0 to disable debouncing.
   * @default 0.5
   */
  barcodeEmissionInterval?: CodegenTypes.WithDefault<CodegenTypes.Double, 0.5>;

  onBarcodeScanned?: CodegenTypes.DirectEventHandler<BarcodeScannedEventPayload>;
  onScannerError?: CodegenTypes.DirectEventHandler<ScannerErrorEventPayload>;
  onLoad?: CodegenTypes.DirectEventHandler<OnLoadEventPayload>;
}

// Explicit type so the emitted .d.ts doesn't reference react-native/types_generated,
// which react-native's package exports block (ScannerView would become `any`)
export default codegenNativeComponent<NativeProps>(
  'ScannerView'
) as HostComponent<NativeProps>;
