import { useCameraInfo } from '@cleanuidev/react-native-scanner';
import { fireEvent, render, screen } from '@testing-library/react-native';
import App from '../src/App';
import { cameraInfo, mockPermission } from '../test-utils';

beforeEach(() => {
  mockPermission('granted');
  jest.mocked(useCameraInfo).mockReturnValue(cameraInfo({ isLoading: true }));
});

describe('Home screen', () => {
  it('lists every example, marking placeholders as coming soon', async () => {
    await render(<App />);

    expect(screen.getByText('React Native Scanner')).toBeOnTheScreen();
    for (const title of [
      'Full Screen Scanner',
      'New Props Example',
      'Rectangular Frame Scanner',
      'Barcode Frame Visualization',
      'Camera Info',
      'Barcode Scan Strategy',
      'Basic Scanner',
      'Custom Frame Scanner',
      'Multi-Format Scanner',
    ]) {
      expect(screen.getByText(title)).toBeOnTheScreen();
    }
    expect(screen.getAllByText('Coming Soon')).toHaveLength(3);
  });

  // Each card opens its screen; matched on text unique to that screen
  it.each([
    ['Full Screen Scanner', '🔄 Change Position'],
    ['New Props Example', 'Barcode Frames Controls'],
    ['Rectangular Frame Scanner', 'Frame Type: Rectangular'],
    ['Barcode Frame Visualization', 'Focus Area Configuration'],
    ['Camera Info', 'Loading camera information...'],
    ['Barcode Scan Strategy', 'Select Strategy:'],
  ])('"%s" opens its example screen', async (card, screenText) => {
    await render(<App />);

    await fireEvent.press(screen.getByText(card));

    expect(await screen.findByText(screenText)).toBeOnTheScreen();
  });

  it('does not navigate for coming soon examples', async () => {
    await render(<App />);

    await fireEvent.press(screen.getByText('Basic Scanner'));

    expect(screen.queryByTestId('scanner-view')).not.toBeOnTheScreen();
    expect(screen.getByText('React Native Scanner')).toBeOnTheScreen();
  });
});

describe('Camera Info screen', () => {
  it('goes back to Home with the back button', async () => {
    await render(<App />);
    await fireEvent.press(screen.getByText('Camera Info'));

    await fireEvent.press(await screen.findByText('← Back'));

    expect(
      screen.queryByText('Loading camera information...')
    ).not.toBeOnTheScreen();
  });
});
