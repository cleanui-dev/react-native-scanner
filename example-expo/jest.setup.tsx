import { Alert } from 'react-native';
import { check, request } from 'react-native-permissions';

// The scanner is a native camera view, so tests replace it with a plain View
// that exposes the props each screen passes to it (torch, zoom, callbacks, ...)
jest.mock('@cleanuidev/react-native-scanner', () => {
  const React = require('react');
  const { View } = require('react-native');
  // Real enums (BarcodeFormat, BarcodeScanStrategy) from the library source
  const types = jest.requireActual('../src/types');

  const ScannerView = (props: object) =>
    React.createElement(View, { ...props, testID: 'scanner-view' });

  return { ...types, ScannerView, useCameraInfo: jest.fn() };
});

jest.mock('react-native-permissions', () =>
  require('react-native-permissions/mock')
);

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default
);

jest.mock('react-native-system-navigation-bar', () => ({
  __esModule: true,
  default: { setNavigationColor: jest.fn(() => Promise.resolve()) },
}));

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(check).mockResolvedValue('granted');
  jest.mocked(request).mockResolvedValue('granted');
  jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  // The example screens log scan results; keep test output readable
  jest.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});
