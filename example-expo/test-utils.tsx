import { Alert, type AlertButton } from 'react-native';
import { act, fireEvent, render, screen } from '@testing-library/react-native';
import { check, request } from 'react-native-permissions';
import type { PermissionStatus } from 'react-native-permissions';
import type {
  CameraInfo,
  UseCameraInfoReturn,
} from '@cleanuidev/react-native-scanner';
import App from './src/App';

type Barcode = {
  data: string;
  format: string;
  timestamp: number;
  area?: number;
  boundingBox?: { left: number; top: number; right: number; bottom: number };
};

export const QR: Barcode = {
  data: 'https://example.com',
  format: 'QR_CODE',
  timestamp: 1,
  area: 2500,
};

export const EAN: Barcode = {
  data: '4006381333931',
  format: 'EAN_13',
  timestamp: 2,
  area: 900,
};

export function mockPermission(
  status: PermissionStatus,
  afterRequest: PermissionStatus = 'granted'
) {
  jest.mocked(check).mockResolvedValue(status);
  jest.mocked(request).mockResolvedValue(afterRequest);
}

/** Renders the app and opens an example from the Home screen, like a user */
export async function openExample(cardTitle: string) {
  await render(<App />);
  await fireEvent.press(screen.getByText(cardTitle));
}

/** Props the screen passed to the (mocked) native ScannerView */
export function scannerProps() {
  return screen.getByTestId('scanner-view').props;
}

export async function emitScan(barcodes: Barcode[]) {
  await act(() =>
    scannerProps().onBarcodeScanned({ nativeEvent: { barcodes } })
  );
}

export async function emitScannerError(error: string, code: string) {
  await act(() =>
    scannerProps().onScannerError({ nativeEvent: { error, code } })
  );
}

export function lastAlert() {
  const calls = jest.mocked(Alert.alert).mock.calls;
  const [title, message, buttons] = calls[calls.length - 1] ?? [];
  return { title, message, buttons: (buttons ?? []) as AlertButton[] };
}

export async function pressAlertButton(text: string) {
  const button = lastAlert().buttons.find((b) => b.text === text);
  if (!button) {
    throw new Error(`Alert has no "${text}" button`);
  }
  await act(() => button.onPress?.());
}

const backCamera: CameraInfo = {
  id: '0',
  facing: 'back',
  sensorOrientation: 90,
  minFocusDistance: 0.1,
  hasFlash: true,
  isMacroCamera: false,
  zoomMin: 1,
  zoomMax: 8,
  focalLengths: ['4.25'],
  aeModes: [],
  afModes: [],
};

const frontCamera: CameraInfo = {
  ...backCamera,
  id: '1',
  facing: 'front',
  sensorOrientation: 270,
  hasFlash: false,
  zoomMax: 4,
  focalLengths: ['2.71'],
};

/** A complete useCameraInfo() result for a two-camera phone */
export function cameraInfo(
  overrides: Partial<UseCameraInfoReturn> = {}
): UseCameraInfoReturn {
  const cameras = [backCamera, frontCamera];
  return {
    deviceInfo: {
      cameras,
      defaultBackCamera: backCamera.id,
      defaultFrontCamera: frontCamera.id,
    },
    currentCameraInfo: null,
    allCameras: cameras,
    backCameras: [backCamera],
    frontCameras: [frontCamera],
    macroCameras: [],
    hasMultipleCameras: true,
    hasBackCamera: true,
    hasFrontCamera: true,
    hasMacroCamera: false,
    hasTorch: true,
    defaultBackCamera: backCamera,
    defaultFrontCamera: frontCamera,
    maxZoom: 8,
    minZoom: 1,
    isLoading: false,
    error: null,
    refreshInfo: jest.fn(() => Promise.resolve()),
    getCameraById: jest.fn(() => null),
    getCamerasByFacing: jest.fn(() => []),
    ...overrides,
  };
}
