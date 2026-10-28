import { act, fireEvent, screen } from '@testing-library/react-native';
import {
  QR,
  emitScan,
  lastAlert,
  mockPermission,
  openExample,
  pressAlertButton,
  scannerProps,
} from '../test-utils';

beforeEach(() => {
  mockPermission('granted');
});

async function openAutoZoom() {
  await openExample('Auto Zoom & Focus');
  await screen.findByTestId('scanner-view');
}

async function emitZoomChange(zoom: number) {
  await act(() => scannerProps().onZoomChange({ nativeEvent: { zoom } }));
}

describe('Auto Zoom & Focus example', () => {
  it('enables auto-zoom, gestures and a centered focus area by default', async () => {
    await openAutoZoom();

    expect(scannerProps()).toMatchObject({
      zoom: 1,
      autoZoom: true,
      maxAutoZoom: 5,
      enablePinchToZoom: true,
      enableTapToFocus: true,
      focusArea: {
        enabled: true,
        showOverlay: true,
        position: { x: 50, y: 50 },
        size: { width: 220, height: 220 },
      },
      barcodeFrames: { enabled: true, onlyInFocusArea: false },
    });
  });

  it('shows the zoom reported by the scanner', async () => {
    await openAutoZoom();
    expect(screen.getByText('1.0x')).toBeOnTheScreen();

    await emitZoomChange(2.75);

    expect(screen.getByText('2.8x')).toBeOnTheScreen();
  });

  it('toggles auto-zoom and the gestures', async () => {
    await openAutoZoom();
    const [autoZoom, pinch, tap] = screen.getAllByRole('switch');

    await fireEvent(autoZoom!, 'valueChange', false);
    await fireEvent(pinch!, 'valueChange', false);
    await fireEvent(tap!, 'valueChange', false);

    expect(scannerProps()).toMatchObject({
      autoZoom: false,
      enablePinchToZoom: false,
      enableTapToFocus: false,
    });
    expect(screen.getByText('Manual zoom only')).toBeOnTheScreen();
  });

  it('adjusts max auto zoom and base zoom within their limits', async () => {
    await openAutoZoom();
    const [maxMinus, maxPlus, baseMinus, basePlus] =
      screen.getAllByText(/^[-+]$/);

    await fireEvent.press(maxPlus!);
    await fireEvent.press(basePlus!);
    expect(scannerProps()).toMatchObject({ maxAutoZoom: 6, zoom: 1.5 });

    await fireEvent.press(baseMinus!);
    await fireEvent.press(baseMinus!);
    for (let i = 0; i < 10; i++) {
      await fireEvent.press(maxMinus!);
    }
    expect(scannerProps()).toMatchObject({ maxAutoZoom: 1, zoom: 1 });
  });

  it('moves and resizes the focus area', async () => {
    await openAutoZoom();

    await fireEvent.press(screen.getByText('Top'));
    await fireEvent.press(screen.getByText('Wide (1D barcodes)'));

    expect(scannerProps().focusArea).toMatchObject({
      position: { x: 50, y: 30 },
      size: { width: 300, height: 120 },
    });
  });

  it('turns the focus area off', async () => {
    await openAutoZoom();
    const [, , , focusArea] = screen.getAllByRole('switch');

    await fireEvent(focusArea!, 'valueChange', false);

    expect(scannerProps().focusArea).toMatchObject({
      enabled: false,
      showOverlay: false,
    });
  });

  it('records the zoom a barcode was scanned at', async () => {
    await openAutoZoom();
    await emitZoomChange(3);

    await emitScan([QR]);

    expect(lastAlert().title).toBe('Barcode Scanned!');
    expect(scannerProps().pauseScanning).toBe(true);
    expect(screen.getByText(`${QR.format} at 3.0x zoom`)).toBeOnTheScreen();

    await pressAlertButton('OK');
    expect(scannerProps().pauseScanning).toBe(false);
  });
});
