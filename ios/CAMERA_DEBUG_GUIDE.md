# Camera Not Working - Debugging Guide

## What to Check on Your iPhone

### 1. **Check Console Logs**
Open Xcode → Window → Devices and Simulators → Select your device → View Device Logs

Look for these log messages:
- `✅ ScannerViewImpl initialized successfully` - Swift class found
- `✅ Delegate set successfully` - Delegate connected
- `✅ View hierarchy setup complete` - Views added
- `[CameraManager] Preview layer created` - Camera setup started
- `[ScannerViewImpl] Preview layer added` - Camera preview added to view

### 2. **Check Camera Permission**
When you first open the app, you should see a system prompt asking:
> "ScannerExample would like to access the camera"

If you don't see this:
- Go to Settings → ScannerExample → Check if Camera is enabled
- If denied, enable it and restart the app

### 3. **Check for Error Messages**
Look for these ERROR indicators in logs:
- `❌ ERROR: ScannerViewImpl class not found` - Swift not linked
- `[CameraManager] Camera permission denied` - Permission issue
- Any other error messages with details

## Common Issues & Solutions

### Issue 1: Black Screen (No Camera Feed)
**Possible Causes:**
- Camera permission not granted
- Swift class not loading
- Preview layer not added properly

**Check:**
```
Settings → Privacy & Security → Camera → ScannerExample → ON
```

### Issue 2: App Crashes
**Likely Cause:** Missing @objc annotations or protocol conformance

### Issue 3: Nothing Happens
**Likely Cause:** Swift module not properly linked to Objective-C++

## Manual Testing Commands

### View Device Logs (if you have Xcode Command Line Tools):
```bash
xcrun simctl spawn booted log stream --predicate 'subsystem contains "scanner" OR eventMessage contains "Scanner"' --level debug
```

### Or use idevicesyslog (if installed):
```bash
idevicesyslog | grep -i scanner
```

## Quick Debug Steps

1. **Open the app on your iPhone**
2. **Look at the screen** - Do you see:
   - Black screen only?
   - Camera permission prompt?
   - Camera feed?
   - Any UI elements?

3. **Try these actions:**
   - Shake the device (opens React Native debug menu)
   - Select "Reload" from the debug menu
   - Check if there are any red error screens

## What Should Happen

When working correctly, you should see:
1. ✅ Camera permission prompt (first time)
2. ✅ Live camera feed fills the screen
3. ✅ Focus area overlay (if enabled in props)
4. ✅ Console logs showing successful initialization

---

**Please tell me:**
1. Do you see a camera permission prompt?
2. What do you see on the screen?
3. Can you access device logs in Xcode?

