import { screen, fireEvent } from '@testing-library/react-native';
import { check, openSettings, request } from 'react-native-permissions';
import { mockPermission, openExample } from '../test-utils';

// Every screen that shows the camera gates it behind the camera permission
describe.each([
  'Full Screen Scanner',
  'New Props Example',
  'Rectangular Frame Scanner',
  'Barcode Frame Visualization',
])('%s camera permission', (card) => {
  it('shows a placeholder while the permission is being checked', async () => {
    jest.mocked(check).mockReturnValue(new Promise(() => {}));

    await openExample(card);

    expect(
      await screen.findByText('Checking camera permission...')
    ).toBeOnTheScreen();
    expect(screen.queryByTestId('scanner-view')).not.toBeOnTheScreen();
  });

  it('shows the scanner when permission is already granted', async () => {
    mockPermission('granted');

    await openExample(card);

    expect(await screen.findByTestId('scanner-view')).toBeOnTheScreen();
    expect(request).not.toHaveBeenCalled();
  });

  it('asks for permission when denied, then shows the scanner', async () => {
    mockPermission('denied', 'granted');
    await openExample(card);

    await fireEvent.press(await screen.findByText('Grant Permission'));

    expect(request).toHaveBeenCalledTimes(1);
    expect(await screen.findByTestId('scanner-view')).toBeOnTheScreen();
  });

  it('keeps the scanner hidden when permission is blocked', async () => {
    mockPermission('blocked');

    await openExample(card);

    expect(
      await screen.findByText(
        'Camera permission is blocked. Please enable it in settings.'
      )
    ).toBeOnTheScreen();
    expect(screen.queryByTestId('scanner-view')).not.toBeOnTheScreen();
  });
});

describe('Full Screen Scanner permission', () => {
  it('opens system settings when permission is blocked', async () => {
    mockPermission('blocked');
    await openExample('Full Screen Scanner');

    await fireEvent.press(await screen.findByText('Open Settings'));

    expect(openSettings).toHaveBeenCalledTimes(1);
  });

  it('explains when the camera is unavailable', async () => {
    mockPermission('unavailable');

    await openExample('Full Screen Scanner');

    expect(
      await screen.findByText('Camera permission is unavailable.')
    ).toBeOnTheScreen();
  });
});
