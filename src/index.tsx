import type { ViewProps } from 'react-native';
import { requireNativeComponent } from 'react-native';
import type {
  BarcodeScannedEventPayload,
  ScannerErrorEventPayload,
  OnLoadEventPayload,
} from './types';
import { BarcodeFormat } from './types';

export { BarcodeFormat } from './types';

const ScannerViewNativeComponent = requireNativeComponent<{
  barcodeTypes?: BarcodeFormat[];
  enableFrame?: boolean;
  frameColor?: string;
  frameSize?: number;
  torch?: boolean;
  zoom?: number;
  pauseScanning?: boolean;
  onBarcodeScanned?: (event: {
    nativeEvent: BarcodeScannedEventPayload;
  }) => void;
  onScannerError?: (event: { nativeEvent: ScannerErrorEventPayload }) => void;
  onLoad?: (event: { nativeEvent: OnLoadEventPayload }) => void;
}>('ScannerView');

export interface ScannerViewProps extends ViewProps {
  // Barcode configuration
  barcodeTypes?: BarcodeFormat[];

  // Frame configuration
  enableFrame?: boolean;
  frameColor?: string;
  frameSize?: number;

  // Camera configuration
  torch?: boolean;
  zoom?: number;
  pauseScanning?: boolean;

  // Event handlers
  onBarcodeScanned?: (event: {
    nativeEvent: BarcodeScannedEventPayload;
  }) => void;
  onScannerError?: (event: { nativeEvent: ScannerErrorEventPayload }) => void;
  onLoad?: (event: { nativeEvent: OnLoadEventPayload }) => void;
}

export default function ScannerView(props: ScannerViewProps) {
  return <ScannerViewNativeComponent {...props} />;
}
