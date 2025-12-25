# iOS Implementation - Build Instructions

## ✅ Implementation Complete!

All Swift code has been implemented. Now it's time to test!

## 📋 Steps to Build and Test

### 1. Clean and Reinstall Pods

```bash
cd /Users/rahulgupta-macmini/Documents/github/rahulgwebdev/react-native-scanner/example/ios

# Clean everything
rm -rf Pods Podfile.lock ~/Library/Developer/Xcode/DerivedData/ScannerExample-*

# Reinstall pods
pod install
```

### 2. Open Workspace in Xcode

```bash
# IMPORTANT: Open the .xcworkspace, NOT .xcodeproj
open ScannerExample.xcworkspace
```

### 3. Configure Code Signing

In Xcode:
1. Select **ScannerExample** project in left sidebar
2. Select **ScannerExample** target
3. Go to **Signing & Capabilities** tab
4. Select your Apple ID under **Team**
5. Change **Bundle Identifier** to something unique if needed

### 4. Connect Your iPhone

1. Connect iPhone via USB
2. Unlock iPhone
3. Trust computer if prompted
4. Select your iPhone from device dropdown in Xcode toolbar

### 5. Build & Run

**Option A: From Xcode**
- Click Play button (⌘ + R)

**Option B: From Terminal**
```bash
cd /Users/rahulgupta-macmini/Documents/github/rahulgwebdev/react-native-scanner/example

# List devices
npx react-native run-ios --list-devices

# Run on your device
npx react-native run-ios --device "Your iPhone Name"
```

## 🐛 Common Build Issues & Solutions

### Issue: "No such module 'react_native_scanner'"

**Solution:**
```bash
cd example/ios
pod deintegrate
pod install
```

Then clean build in Xcode: **Product → Clean Build Folder** (⇧⌘K)

### Issue: Bridging header not found

**Solution:**
The bridging header should be auto-generated. If not:
1. In Xcode, go to **Build Settings**
2. Search for "Objective-C Bridging Header"
3. Set to: `$(PODS_ROOT)/../../../ios/react-native-scanner-Bridging-Header.h`

### Issue: Swift files not compiling

**Solution:**
Check that Scanner.podspec includes:
```ruby
s.source_files = "ios/**/*.{h,m,mm,cpp,swift}"
s.swift_version = '5.0'
```

### Issue: "Use of undeclared identifier"

**Solution:**
Make sure you're opening the **.xcworkspace** file, not .xcodeproj

## 📱 Testing Checklist

Once the app launches:

### Basic Functionality
- [ ] Camera preview appears
- [ ] Can scan QR codes
- [ ] Can scan barcodes (Code 128, EAN-13, etc.)
- [ ] Scanned data logs to console

### Focus Area
- [ ] Focus area overlay appears when enabled
- [ ] Can configure square focus area
- [ ] Can configure rectangular focus area
- [ ] Focus area position works (center, custom)
- [ ] Only scans barcodes in focus area when enabled

### Barcode Frames
- [ ] Red rectangles appear around detected barcodes
- [ ] Frames update in real-time
- [ ] Frames disappear after timeout
- [ ] "Only in focus area" works

### Controls
- [ ] Torch/flashlight works
- [ ] Zoom works
- [ ] Pause scanning works
- [ ] Resume scanning works

### Scan Strategies
- [ ] ONE - returns single barcode
- [ ] ALL - returns all barcodes
- [ ] BIGGEST - returns largest barcode
- [ ] SORT_BY_BIGGEST - returns sorted barcodes

### Performance
- [ ] No lag or stuttering
- [ ] Memory usage stable
- [ ] Battery usage reasonable
- [ ] No crashes

## 🔍 Debugging Tips

### View Console Logs

In Xcode, look for logs prefixed with:
- `[CameraManager]`
- `[BarcodeDetectionManager]`
- `[ScannerViewImpl]`
- `[BarcodeFrameManager]`

### Print Sample Barcode Data

Add this to your example app:
```javascript
onBarcodeScanned={(event) => {
  console.log('Detected:', JSON.stringify(event.nativeEvent, null, 2));
}}
```

### Test QR Codes

Generate test QR codes at: https://www.qr-code-generator.com/

### Debug Coordinate Transformation

In `CoordinateTransformer.swift`, add print statements:
```swift
print("Vision rect: \(visionRect)")
print("View rect: \(rect)")
```

## 🎉 Success Criteria

App is working when:
1. ✅ Camera preview displays
2. ✅ Barcode detection works
3. ✅ Focus area renders correctly
4. ✅ Barcode frames appear around codes
5. ✅ All props respond to changes
6. ✅ No memory leaks
7. ✅ Performs well on device

## 🚀 Next Steps After Testing

1. Fix any bugs found during testing
2. Optimize performance if needed
3. Test edge cases (poor lighting, damaged barcodes, etc.)
4. Test on different iOS devices
5. Test on different iOS versions
6. Add unit tests
7. Add UI tests
8. Update documentation

## 📝 Known Limitations

1. **Coordinate transformation** may need fine-tuning for different devices/orientations
2. **Video gravity** handling is simplified (works for ResizeAspectFill)
3. **Device orientation** changes may need additional handling
4. **Multiple cameras** not yet supported (only back camera)

## 💡 Tips for Success

1. Test with **real barcodes/QR codes** (not just screen images)
2. Test in **different lighting conditions**
3. Test with **multiple barcodes** in view
4. Test **focus area** with various sizes and positions
5. Monitor **performance** with Instruments

---

**Ready to build?** Follow the steps above and let's see it work! 🎯

