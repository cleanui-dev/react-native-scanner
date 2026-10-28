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

export interface ZoomChangeEventPayload {
  zoom: CodegenTypes.Double;
}

// Event types for use in handlers, taken from the props so they always match
// what ScannerView passes (react-native's strict API adds fields to these events)
type EventOf<Handler extends ((event: never) => unknown) | undefined> =
  Parameters<NonNullable<Handler>>[0];
export type BarcodeScannedEvent = EventOf<NativeProps['onBarcodeScanned']>;
export type ScannerErrorEvent = EventOf<NativeProps['onScannerError']>;
export type OnLoadEvent = EventOf<NativeProps['onLoad']>;
export type ZoomChangeEvent = EventOf<NativeProps['onZoomChange']>;

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

  /**
   * Smart zoom for small or distant barcodes; returns to `zoom` after a short idle period.
   * Only barcodes inside the focus area drive the zoom when the focus area is enabled or
   * shown, and zoom is capped so the barcode stays inside it. Zooms out when a barcode
   * overflows the focus area.
   * - Android: zooms in on barcodes ML Kit detects but can't decode yet.
   * - iOS: Vision only reports decodable barcodes, so instead the starting zoom is raised on
   *   devices with a long minimum focus distance so codes are held at a focusable distance.
   * @default true
   */
  autoZoom?: CodegenTypes.WithDefault<boolean, true>;

  /**
   * Upper bound for automatic zoom (also clamped to the device maximum).
   * @default 5
   */
  maxAutoZoom?: CodegenTypes.WithDefault<CodegenTypes.Double, 5.0>;

  /**
   * Allow pinch gesture on the preview to zoom.
   * @default true
   */
  enablePinchToZoom?: CodegenTypes.WithDefault<boolean, true>;

  /**
   * Allow tapping the preview to focus at that point.
   * @default true
   */
  enableTapToFocus?: CodegenTypes.WithDefault<boolean, true>;

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
  /** Fired when the zoom ratio changes from auto-zoom or pinch-to-zoom. */
  onZoomChange?: CodegenTypes.DirectEventHandler<ZoomChangeEventPayload>;
}

// Explicit type so the emitted .d.ts doesn't reference react-native/types_generated,
// which react-native's package exports block (ScannerView would become `any`)
export default codegenNativeComponent<NativeProps>(
  'ScannerView'
) as HostComponent<NativeProps>;
