# Fabric Component Registration Fix

## Issue
After the app successfully built and launched, we encountered this runtime error:
```
Warning: Invariant Violation: View config not found for component `ScannerView`
```

## Root Cause
The JavaScript code was using the **legacy** `requireNativeComponent` API instead of the **New Architecture (Fabric)** codegen component. 

When `RCT_NEW_ARCH_ENABLED = '1'`, React Native expects components to be registered using the codegen system, not the old bridge system.

## Solution

### Updated `/src/index.tsx`

**Before** (using legacy API):
```typescript
import { requireNativeComponent } from 'react-native';

const ScannerViewNativeComponent = requireNativeComponent<{
  // ... props
}>('ScannerView');
```

**After** (using Fabric/codegen):
```typescript
import ScannerViewNativeComponent from './ScannerViewNativeComponent';

export default function ScannerView(props: ScannerViewProps) {
  const nativeProps = {
    ...props,
    barcodeTypes: props.barcodeTypes?.map(String),
  };
  
  return <ScannerViewNativeComponent {...nativeProps} />;
}
```

### Key Changes:
1. **Import the codegen component** from `./ScannerViewNativeComponent.ts`
2. **Remove `requireNativeComponent` call** - not needed for Fabric
3. **Map props to match native interface** - ensure barcode types are strings

## Technical Details

The codegen component (`ScannerViewNativeComponent.ts`) uses:
```typescript
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

export default codegenNativeComponent<NativeProps>(
  'ScannerView'
) as HostComponent<NativeProps>;
```

This is automatically registered with Fabric at build time through:
- C++ code generation from the TypeScript spec
- Component descriptor provider in `ScannerView.mm`
- Fabric component registry

## Expected Result
✅ Component should now be recognized by React Native's Fabric system  
✅ No more "View config not found" errors  
✅ Native Swift code will be properly connected to JavaScript

## Build Status
Currently rebuilding the app with the corrected imports...

---
*Date: December 25, 2025*
*Architecture: React Native New Architecture (Fabric)*

