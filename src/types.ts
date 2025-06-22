import type { StyleProp, ViewStyle } from 'react-native';

// Barcode format enum
export enum BarcodeFormat {
  QR_CODE = 'QR_CODE',
  CODE_128 = 'CODE_128',
  CODE_39 = 'CODE_39',
  EAN_13 = 'EAN_13',
  EAN_8 = 'EAN_8',
  UPC_A = 'UPC_A',
  UPC_E = 'UPC_E',
  DATA_MATRIX = 'DATA_MATRIX',
  PDF_417 = 'PDF_417',
  AZTEC = 'AZTEC',
  ITF = 'ITF',
}

// Barcode scanned event payload
export type BarcodeScannedEventPayload = {
  data: string;
  format: BarcodeFormat;
  timestamp: number;
};

// Scanner error event payload
export type ScannerErrorEventPayload = {
  error: string;
  code: string;
};

// On load event payload (for camera initialization)
export type OnLoadEventPayload = {
  success: boolean;
  error?: string;
};

// Event types
export type CameraNativeModuleEvents = {
  onBarcodeScanned: (params: BarcodeScannedEventPayload) => void;
  onScannerError: (params: ScannerErrorEventPayload) => void;
  onLoad: (params: OnLoadEventPayload) => void;
};

// Props interface for the scanner view
export type CameraNativeModuleViewProps = {
  // Barcode configuration
  barcodeTypes?: BarcodeFormat[];

  // Frame configuration
  enableFrame?: boolean;
  frameColor?: string;

  // Torch control
  torch?: boolean;

  // Event handlers
  onBarcodeScanned?: (event: {
    nativeEvent: BarcodeScannedEventPayload;
  }) => void;
  onScannerError?: (event: { nativeEvent: ScannerErrorEventPayload }) => void;
  onLoad?: (event: { nativeEvent: OnLoadEventPayload }) => void;

  // Styling
  style?: StyleProp<ViewStyle>;
};

// Method invokers for controlling the scanner
export type CameraNativeModuleMethods = {
  toggleTorch: () => Promise<boolean>;
  startScanning: () => Promise<void>;
  stopScanning: () => Promise<void>;
  isTorchAvailable: () => Promise<boolean>;
};
