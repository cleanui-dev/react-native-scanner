import { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  Text,
  TouchableOpacity,
  Alert,
  Platform,
  Switch,
  ScrollView,
} from 'react-native';
import {
  ScannerView,
  BarcodeFormat,
  BarcodeScanStrategy,
  type BarcodeScannedEvent,
  type ZoomChangeEvent,
} from '@cleanuidev/react-native-scanner';
import { check, request, PERMISSIONS, RESULTS } from 'react-native-permissions';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { useReliableInsets } from '../hooks';

// Focus area positions (percent of the view). Off-center positions show that auto-zoom
// keeps the barcode inside the focus area instead of zooming it out of the frame.
const FOCUS_POSITIONS = [
  { label: 'Center', position: { x: 50, y: 50 } },
  { label: 'Top', position: { x: 50, y: 30 } },
  { label: 'Bottom', position: { x: 50, y: 70 } },
  { label: 'Left', position: { x: 35, y: 50 } },
  { label: 'Right', position: { x: 65, y: 50 } },
];

const FOCUS_SIZES = [
  { label: 'Square', size: { width: 220, height: 220 } },
  { label: 'Wide (1D barcodes)', size: { width: 300, height: 120 } },
];

export default function AutoZoomExample() {
  const [pauseScanning, setPauseScanning] = useState(false);
  const [permission, setPermission] = useState<
    'granted' | 'denied' | 'blocked' | 'unavailable' | 'limited' | 'loading'
  >('loading');

  // Zoom & focus behavior
  const [autoZoom, setAutoZoom] = useState(true);
  const [maxAutoZoom, setMaxAutoZoom] = useState(5);
  const [enablePinchToZoom, setEnablePinchToZoom] = useState(true);
  const [enableTapToFocus, setEnableTapToFocus] = useState(true);
  const [baseZoom, setBaseZoom] = useState(1);
  const [currentZoom, setCurrentZoom] = useState(1);

  // Focus area
  const [focusAreaEnabled, setFocusAreaEnabled] = useState(true);
  const [positionIndex, setPositionIndex] = useState(0);
  const [sizeIndex, setSizeIndex] = useState(0);

  const [lastScan, setLastScan] = useState<{
    data: string;
    format: string;
    zoom: number;
  } | null>(null);

  const insets = useReliableInsets();

  useEffect(() => {
    const checkPermission = async () => {
      setPermission('loading');
      const result = await check(
        Platform.OS === 'android'
          ? PERMISSIONS.ANDROID.CAMERA
          : PERMISSIONS.IOS.CAMERA
      );
      setPermission(result);
    };
    checkPermission();
  }, []);

  const requestPermission = async () => {
    const result = await request(
      Platform.OS === 'android'
        ? PERMISSIONS.ANDROID.CAMERA
        : PERMISSIONS.IOS.CAMERA
    );
    setPermission(result);
  };

  const handleBarcodeScanned = (event: BarcodeScannedEvent) => {
    const barcode = event.nativeEvent.barcodes[0];
    if (!barcode) {
      return;
    }

    setPauseScanning(true);
    setLastScan({
      data: barcode.data,
      format: barcode.format,
      zoom: currentZoom,
    });

    Alert.alert(
      'Barcode Scanned!',
      `Data: ${barcode.data}\nFormat: ${barcode.format}`,
      [
        {
          text: 'OK',
          onPress: () => {
            setPauseScanning(false);
          },
        },
      ],
      {
        onDismiss: () => {
          setPauseScanning(false);
        },
      }
    );
  };

  const handleZoomChange = (event: ZoomChangeEvent) => {
    setCurrentZoom(event.nativeEvent.zoom);
  };

  const handleScannerError = (event: {
    nativeEvent: { error: string; code: string };
  }) => {
    Alert.alert(
      'Scanner Error',
      `Error: ${event.nativeEvent.error}\nCode: ${event.nativeEvent.code}`,
      [{ text: 'OK' }]
    );
  };

  const changeBaseZoom = (delta: number) => {
    const next = Math.min(Math.max(baseZoom + delta, 1), 5);
    setBaseZoom(next);
    setCurrentZoom(next);
  };

  const changeMaxAutoZoom = (delta: number) => {
    setMaxAutoZoom((prev) => Math.min(Math.max(prev + delta, 1), 10));
  };

  if (permission === 'loading') {
    return <Text>Checking camera permission...</Text>;
  }

  if (permission === RESULTS.DENIED) {
    return (
      <View style={styles.container}>
        <Text>Camera permission is required</Text>
        <TouchableOpacity style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>Grant Permission</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (permission === RESULTS.BLOCKED) {
    return (
      <View style={styles.container}>
        <Text>Camera permission is blocked. Please enable it in settings.</Text>
      </View>
    );
  }

  const focusPosition = FOCUS_POSITIONS[positionIndex]!;
  const focusSize = FOCUS_SIZES[sizeIndex]!;

  return (
    <SafeAreaProvider>
      <View style={[styles.container, { paddingTop: insets.top }]}>
        <View style={styles.scannerContainer}>
          <ScannerView
            style={styles.scanner}
            barcodeTypes={[
              BarcodeFormat.QR_CODE,
              BarcodeFormat.CODE_128,
              BarcodeFormat.EAN_13,
              BarcodeFormat.EAN_8,
              BarcodeFormat.UPC_A,
              BarcodeFormat.DATA_MATRIX,
            ]}
            focusArea={{
              enabled: focusAreaEnabled,
              showOverlay: focusAreaEnabled,
              size: focusSize.size,
              position: focusPosition.position,
              borderColor: '#00E676',
            }}
            // Frames on every barcode make it visible that barcodes outside the
            // focus area are detected but never drive the zoom
            barcodeFrames={{
              enabled: true,
              color: '#FF3B30',
              onlyInFocusArea: false,
            }}
            zoom={baseZoom}
            autoZoom={autoZoom}
            maxAutoZoom={maxAutoZoom}
            enablePinchToZoom={enablePinchToZoom}
            enableTapToFocus={enableTapToFocus}
            onZoomChange={handleZoomChange}
            pauseScanning={pauseScanning}
            barcodeScanStrategy={BarcodeScanStrategy.BIGGEST}
            onBarcodeScanned={handleBarcodeScanned}
            onScannerError={handleScannerError}
          />

          <View style={styles.zoomBadge} pointerEvents="none">
            <Text style={styles.zoomBadgeText}>{currentZoom.toFixed(1)}x</Text>
          </View>

          <View style={styles.hint} pointerEvents="none">
            <Text style={styles.hintText}>
              {[
                autoZoom && 'Auto-zoom on',
                enablePinchToZoom && 'Pinch to zoom',
                enableTapToFocus && 'Tap to focus',
              ]
                .filter(Boolean)
                .join(' · ') || 'Manual zoom only'}
            </Text>
          </View>
        </View>

        <ScrollView
          contentContainerStyle={{ paddingBottom: insets.bottom }}
          style={styles.controlsContainer}
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.controlSection}>
            <Text style={styles.sectionTitle}>Zoom & Focus</Text>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>Auto Zoom</Text>
              <Switch
                value={autoZoom}
                onValueChange={setAutoZoom}
                trackColor={{ false: '#767577', true: '#81b0ff' }}
                thumbColor={autoZoom ? '#f5dd4b' : '#f4f3f4'}
              />
            </View>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>
                Max Auto Zoom: {maxAutoZoom}x
              </Text>
              <View style={styles.stepper}>
                <TouchableOpacity
                  style={styles.smallButton}
                  onPress={() => changeMaxAutoZoom(-1)}
                  disabled={!autoZoom}
                >
                  <Text style={styles.buttonText}>-</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.smallButton}
                  onPress={() => changeMaxAutoZoom(1)}
                  disabled={!autoZoom}
                >
                  <Text style={styles.buttonText}>+</Text>
                </TouchableOpacity>
              </View>
            </View>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>
                Base Zoom: {baseZoom.toFixed(1)}x
              </Text>
              <View style={styles.stepper}>
                <TouchableOpacity
                  style={styles.smallButton}
                  onPress={() => changeBaseZoom(-0.5)}
                >
                  <Text style={styles.buttonText}>-</Text>
                </TouchableOpacity>
                <TouchableOpacity
                  style={styles.smallButton}
                  onPress={() => changeBaseZoom(0.5)}
                >
                  <Text style={styles.buttonText}>+</Text>
                </TouchableOpacity>
              </View>
            </View>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>Pinch to Zoom</Text>
              <Switch
                value={enablePinchToZoom}
                onValueChange={setEnablePinchToZoom}
                trackColor={{ false: '#767577', true: '#81b0ff' }}
                thumbColor={enablePinchToZoom ? '#f5dd4b' : '#f4f3f4'}
              />
            </View>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>Tap to Focus</Text>
              <Switch
                value={enableTapToFocus}
                onValueChange={setEnableTapToFocus}
                trackColor={{ false: '#767577', true: '#81b0ff' }}
                thumbColor={enableTapToFocus ? '#f5dd4b' : '#f4f3f4'}
              />
            </View>

            <Text style={styles.description}>
              Hold a small code far away inside the green area: the camera zooms
              in until it can read it, then zooms back to the base zoom after a
              couple of seconds without a code.
            </Text>
          </View>

          <View style={styles.controlSection}>
            <Text style={styles.sectionTitle}>Focus Area</Text>

            <View style={styles.controlRow}>
              <Text style={styles.controlLabel}>Only Scan in Focus Area</Text>
              <Switch
                value={focusAreaEnabled}
                onValueChange={setFocusAreaEnabled}
                trackColor={{ false: '#767577', true: '#81b0ff' }}
                thumbColor={focusAreaEnabled ? '#f5dd4b' : '#f4f3f4'}
              />
            </View>

            <Text style={styles.controlLabel}>Position</Text>
            <View style={styles.chips}>
              {FOCUS_POSITIONS.map((item, index) => (
                <TouchableOpacity
                  key={item.label}
                  style={[
                    styles.chip,
                    index === positionIndex && styles.chipSelected,
                  ]}
                  onPress={() => setPositionIndex(index)}
                  disabled={!focusAreaEnabled}
                >
                  <Text
                    style={[
                      styles.chipText,
                      index === positionIndex && styles.chipTextSelected,
                    ]}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <Text style={styles.controlLabel}>Size</Text>
            <View style={styles.chips}>
              {FOCUS_SIZES.map((item, index) => (
                <TouchableOpacity
                  key={item.label}
                  style={[
                    styles.chip,
                    index === sizeIndex && styles.chipSelected,
                  ]}
                  onPress={() => setSizeIndex(index)}
                  disabled={!focusAreaEnabled}
                >
                  <Text
                    style={[
                      styles.chipText,
                      index === sizeIndex && styles.chipTextSelected,
                    ]}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>

            <Text style={styles.description}>
              {focusAreaEnabled
                ? 'Only codes inside the green area drive the zoom, and zoom is capped so the code stays inside it. Codes outside still get a red frame but are ignored.'
                : 'With the focus area off, any code on screen can drive the zoom.'}
            </Text>
          </View>

          {lastScan ? (
            <View style={styles.controlSection}>
              <Text style={styles.sectionTitle}>Last Scanned</Text>
              <Text style={styles.scannedData}>{lastScan.data}</Text>
              <Text style={styles.description}>
                {lastScan.format} at {lastScan.zoom.toFixed(1)}x zoom
              </Text>
            </View>
          ) : null}
        </ScrollView>
      </View>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  scannerContainer: {
    flex: 1,
    position: 'relative',
  },
  scanner: {
    flex: 1,
  },
  zoomBadge: {
    position: 'absolute',
    top: 16,
    alignSelf: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 16,
  },
  zoomBadgeText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
  hint: {
    position: 'absolute',
    bottom: 16,
    alignSelf: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
  },
  hintText: {
    color: '#fff',
    fontSize: 12,
  },
  controlsContainer: {
    backgroundColor: '#fff',
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 40,
    maxHeight: '50%',
  },
  controlSection: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
    color: '#333',
  },
  controlRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  controlLabel: {
    fontSize: 16,
    color: '#333',
    flex: 1,
  },
  description: {
    fontSize: 14,
    color: '#666',
    fontStyle: 'italic',
    marginTop: 8,
  },
  button: {
    backgroundColor: '#007AFF',
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
  },
  buttonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  smallButton: {
    backgroundColor: '#007AFF',
    width: 32,
    height: 32,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: 4,
  },
  stepper: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  chips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    marginTop: 8,
    marginBottom: 12,
  },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#007AFF',
    marginRight: 8,
    marginBottom: 8,
  },
  chipSelected: {
    backgroundColor: '#007AFF',
  },
  chipText: {
    color: '#007AFF',
    fontSize: 14,
  },
  chipTextSelected: {
    color: '#fff',
  },
  scannedData: {
    fontSize: 14,
    color: '#333',
    backgroundColor: '#f0f0f0',
    padding: 12,
    borderRadius: 8,
    fontFamily: 'monospace',
  },
});
