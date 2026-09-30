import { Alert } from 'react-native';
import { fireEvent, screen } from '@testing-library/react-native';
import {
  EAN,
  QR,
  emitScan,
  emitScannerError,
  lastAlert,
  mockPermission,
  openExample,
  pressAlertButton,
  scannerProps,
} from '../test-utils';

beforeEach(() => {
  mockPermission('granted');
});

async function openScanner(card: string) {
  await openExample(card);
  await screen.findByTestId('scanner-view');
}

// Shared scan flow: scan -> alert -> pause until the alert is dismissed
describe.each([
  'Full Screen Scanner',
  'New Props Example',
  'Rectangular Frame Scanner',
  'Barcode Frame Visualization',
])('%s scanning', (card) => {
  it('alerts with the first barcode and pauses scanning', async () => {
    await openScanner(card);
    expect(scannerProps().pauseScanning).toBe(false);

    await emitScan([QR, EAN]);

    expect(lastAlert().title).toBe('Barcode Scanned!');
    expect(lastAlert().message).toBe(`Data: ${QR.data}\nFormat: ${QR.format}`);
    expect(scannerProps().pauseScanning).toBe(true);
  });

  it('resumes scanning when the alert is dismissed', async () => {
    await openScanner(card);
    await emitScan([QR]);

    await pressAlertButton('OK');

    expect(scannerProps().pauseScanning).toBe(false);
  });

  it('ignores scan events without barcodes', async () => {
    await openScanner(card);

    await emitScan([]);

    expect(Alert.alert).not.toHaveBeenCalled();
  });

  it('shows native scanner errors', async () => {
    await openScanner(card);

    await emitScannerError('Camera in use', 'CAMERA_ERROR');

    expect(lastAlert().title).toBe('Scanner Error');
    expect(lastAlert().message).toBe(
      'Error: Camera in use\nCode: CAMERA_ERROR'
    );
  });
});

describe('Full Screen Scanner controls', () => {
  it('passes focus area, formats and camera settings to the scanner', async () => {
    await openScanner('Full Screen Scanner');

    expect(scannerProps()).toMatchObject({
      torch: false,
      zoom: 1,
      keepScreenOn: true,
      focusArea: { size: { width: 300, height: 300 } },
    });
    expect(scannerProps().barcodeTypes).toEqual(
      expect.arrayContaining(['QR_CODE', 'EAN_13', 'CODE_128'])
    );
  });

  it('toggles the torch', async () => {
    await openScanner('Full Screen Scanner');

    await fireEvent.press(screen.getByText('🔦 ON'));

    expect(scannerProps().torch).toBe(true);
    expect(screen.getByText('🔦 OFF')).toBeOnTheScreen();
  });

  it('cycles zoom 1x -> 2x -> 3x -> 1x', async () => {
    await openScanner('Full Screen Scanner');

    for (const expected of [2, 3, 1]) {
      await fireEvent.press(screen.getByText(/^🔍/));
      expect(scannerProps().zoom).toBe(expected);
    }
  });
});

describe('New Props Example controls', () => {
  it('toggles focus area scanning and barcode frames', async () => {
    await openScanner('New Props Example');
    expect(scannerProps().focusArea.enabled).toBe(false);
    expect(scannerProps().barcodeFrames.enabled).toBe(true);

    await fireEvent.press(screen.getByText(/Enable Focus/));
    await fireEvent.press(screen.getByText(/Disable\s+Frames/));

    expect(scannerProps().focusArea.enabled).toBe(true);
    expect(scannerProps().barcodeFrames.enabled).toBe(false);
  });

  it('toggles the torch and cycles zoom', async () => {
    await openScanner('New Props Example');

    await fireEvent.press(screen.getByText('Enable Torch'));
    await fireEvent.press(screen.getByText('Zoom: 1x'));

    expect(scannerProps().torch).toBe(true);
    expect(scannerProps().zoom).toBe(2);
    expect(screen.getByText('Disable Torch')).toBeOnTheScreen();
  });
});

describe('Rectangular Frame Scanner controls', () => {
  it('uses a rectangular focus area', async () => {
    await openScanner('Rectangular Frame Scanner');

    const { width, height } = scannerProps().focusArea.size;
    expect(width).toBeGreaterThan(height);
  });

  it('toggles the torch and focus area', async () => {
    await openScanner('Rectangular Frame Scanner');

    await fireEvent.press(screen.getByText('Enable Torch'));
    await fireEvent.press(screen.getByText('Enable Focus Area'));

    expect(scannerProps().torch).toBe(true);
    expect(scannerProps().focusArea.enabled).toBe(true);
  });
});

describe('Barcode Frame Visualization controls', () => {
  it('shows the last scanned value', async () => {
    await openScanner('Barcode Frame Visualization');

    await emitScan([EAN]);

    expect(screen.getByText('Last Scanned')).toBeOnTheScreen();
    expect(screen.getByText(EAN.data)).toBeOnTheScreen();
  });

  it('only scans inside the focus area by default', async () => {
    await openScanner('Barcode Frame Visualization');

    expect(scannerProps().focusArea).toMatchObject({
      enabled: true,
      showOverlay: true,
      borderColor: '#00FF00',
    });
  });

  it('turns off focus area scanning and its overlay with the switch', async () => {
    await openScanner('Barcode Frame Visualization');
    const focusSwitch = screen.getAllByRole('switch')[0]!;

    await fireEvent(focusSwitch, 'valueChange', false);

    expect(scannerProps().focusArea).toMatchObject({
      enabled: false,
      showOverlay: false,
    });
  });

  it('changes the focus area border color', async () => {
    await openScanner('Barcode Frame Visualization');

    await fireEvent.press(screen.getByText('Change Color'));

    expect(scannerProps().focusArea.borderColor).not.toBe('#00FF00');
  });

  it('turns barcode frames off with the switch', async () => {
    await openScanner('Barcode Frame Visualization');
    const framesSwitch = screen.getAllByRole('switch')[1]!;

    await fireEvent(framesSwitch, 'valueChange', false);

    expect(scannerProps().barcodeFrames.enabled).toBe(false);
  });

  it('keeps zoom between 1x and 3x', async () => {
    await openScanner('Barcode Frame Visualization');

    await fireEvent.press(screen.getByText('-'));
    expect(scannerProps().zoom).toBe(1);

    for (let i = 0; i < 6; i++) {
      await fireEvent.press(screen.getByText('+'));
    }
    expect(scannerProps().zoom).toBe(3);
  });
});
