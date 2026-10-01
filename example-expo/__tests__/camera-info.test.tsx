import { useCameraInfo } from '@cleanuidev/react-native-scanner';
import { fireEvent, screen } from '@testing-library/react-native';
import { cameraInfo, lastAlert, openExample } from '../test-utils';

describe('Camera Info', () => {
  it('shows a loading state', async () => {
    jest.mocked(useCameraInfo).mockReturnValue(cameraInfo({ isLoading: true }));

    await openExample('Camera Info');

    expect(
      await screen.findByText('Loading camera information...')
    ).toBeOnTheScreen();
  });

  it('shows the device cameras and capabilities', async () => {
    jest.mocked(useCameraInfo).mockReturnValue(cameraInfo());

    await openExample('Camera Info');

    expect(await screen.findByText('📱 Device Summary')).toBeOnTheScreen();
    expect(screen.getByText('Default Back Camera')).toBeOnTheScreen();
    expect(screen.getByText('Default Front Camera')).toBeOnTheScreen();
    expect(screen.getByText('Camera 1')).toBeOnTheScreen();
    expect(screen.getByText('Camera 2')).toBeOnTheScreen();
    expect(screen.getByText(/Min: 1\.0x \| Max: 8\.0x/)).toBeOnTheScreen();
  });

  it('refreshes camera information', async () => {
    const info = cameraInfo();
    jest.mocked(useCameraInfo).mockReturnValue(info);
    await openExample('Camera Info');

    await fireEvent.press(await screen.findByText('🔄'));

    expect(info.refreshInfo).toHaveBeenCalledTimes(1);
    expect(lastAlert().title).toBe('Success');
  });

  it('reports a failed refresh', async () => {
    const info = cameraInfo({
      refreshInfo: jest.fn(() => Promise.reject(new Error('No camera'))),
    });
    jest.mocked(useCameraInfo).mockReturnValue(info);
    await openExample('Camera Info');

    await fireEvent.press(await screen.findByText('🔄'));

    expect(lastAlert().title).toBe('Error');
    expect(lastAlert().message).toContain('No camera');
  });

  it('shows errors with a retry button', async () => {
    const info = cameraInfo({ error: 'Camera service unavailable' });
    jest.mocked(useCameraInfo).mockReturnValue(info);
    await openExample('Camera Info');

    expect(
      await screen.findByText('Error: Camera service unavailable')
    ).toBeOnTheScreen();

    await fireEvent.press(screen.getByText('Retry'));

    expect(info.refreshInfo).toHaveBeenCalledTimes(1);
  });
});
