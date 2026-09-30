import { fireEvent, screen } from '@testing-library/react-native';
import {
  EAN,
  QR,
  emitScan,
  lastAlert,
  openExample,
  pressAlertButton,
  scannerProps,
} from '../test-utils';

async function openStrategyScreen() {
  await openExample('Barcode Scan Strategy');
  await screen.findByTestId('scanner-view');
}

describe('Barcode Scan Strategy', () => {
  it('starts with the ALL strategy', async () => {
    await openStrategyScreen();

    expect(scannerProps().barcodeScanStrategy).toBe('ALL');
    expect(screen.getByText('Current Strategy: ALL')).toBeOnTheScreen();
    expect(screen.getByText('No barcodes scanned yet')).toBeOnTheScreen();
  });

  it.each([
    ['ONE - First barcode only', 'ONE'],
    ['BIGGEST - Largest barcode only', 'BIGGEST'],
    ['SORT_BY_BIGGEST - All sorted by size', 'SORT_BY_BIGGEST'],
  ])('selecting "%s" passes %s to the scanner', async (label, strategy) => {
    await openStrategyScreen();

    await fireEvent.press(screen.getByText(label));

    expect(scannerProps().barcodeScanStrategy).toBe(strategy);
    expect(screen.getByText(`Current Strategy: ${strategy}`)).toBeOnTheScreen();
  });

  it('lists every barcode from a scan', async () => {
    await openStrategyScreen();

    await emitScan([QR, EAN]);

    expect(
      screen.getByText('Last Scan Results (2 barcode(s)):')
    ).toBeOnTheScreen();
    expect(screen.getByText(`1. ${QR.data}`)).toBeOnTheScreen();
    expect(screen.getByText(`2. ${EAN.data}`)).toBeOnTheScreen();
    expect(lastAlert().message).toContain(
      'Found 2 barcode(s) using strategy: ALL'
    );
  });

  it('clears results when the strategy changes', async () => {
    await openStrategyScreen();
    await emitScan([QR]);

    await fireEvent.press(screen.getByText('ONE - First barcode only'));

    expect(screen.getByText('No barcodes scanned yet')).toBeOnTheScreen();
  });

  it('stops and resumes scanning from the alert', async () => {
    await openStrategyScreen();
    await emitScan([QR]);

    await pressAlertButton('Stop');

    expect(screen.queryByTestId('scanner-view')).not.toBeOnTheScreen();
    expect(screen.getByText('Scanner Paused')).toBeOnTheScreen();

    await fireEvent.press(screen.getByText('Resume Scanning'));

    expect(screen.getByTestId('scanner-view')).toBeOnTheScreen();
    expect(screen.getByText('No barcodes scanned yet')).toBeOnTheScreen();
  });
});
