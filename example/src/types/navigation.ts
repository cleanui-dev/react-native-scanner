import type { NativeStackNavigationProp } from '@react-navigation/native-stack';

export type RootStackParamList = {
  Home: undefined;
  FullScreenExample: undefined;
  NewPropsExample: undefined;
  RectangularFrameExample: undefined;
  BarcodeFrameExample: undefined;
  CameraInfoExample: undefined;
  BarcodeScanStrategyExample: undefined;
};

export type NavigationProp = NativeStackNavigationProp<
  RootStackParamList,
  'Home'
>;
