# Pod Install Fix for react-native-permissions

## Issue
The initial build failed with the error:
```
[!] No podspec found for `Permission-Camera` in `../node_modules/react-native-permissions/ios/Camera`
```

## Root Cause
The `react-native-permissions` library requires special configuration in the Podfile. It doesn't include individual `.podspec` files for each permission module. Instead, it provides a `setup.rb` script that must be loaded and used to configure permissions.

## Solution
Updated the `example/ios/Podfile` to properly configure react-native-permissions:

### Changes Made:

1. **Added helper function** to require scripts with node resolution:
```ruby
def node_require(script)
  require Pod::Executable.execute_command('node', ['-p',
    "require.resolve(
      '#{script}',
      {paths: [process.argv[1]]},
    )", __dir__]).strip
end
```

2. **Required the permissions setup script**:
```ruby
node_require('react-native/scripts/react_native_pods.rb')
node_require('react-native-permissions/scripts/setup.rb')
```

3. **Added setup_permissions call** inside the target block:
```ruby
target 'ScannerExample' do
  config = use_native_modules!

  # Setup permissions for react-native-permissions
  setup_permissions([
    'Camera',
  ])

  use_react_native!(
    :path => config[:reactNativePath],
    :app_path => "#{Pod::Config.instance.installation_root}/.."
  )
  # ... rest of config
end
```

## Result
✅ Pod install now succeeds
✅ Camera permission is properly configured
✅ Build is proceeding successfully

## Build Status
The iOS build is currently in progress. Once complete, the app will be deployed to the physical iPhone (UDID: 00008120-001179D11A81A01E).

---
*Date: December 25, 2025*
*Status: Build in progress*

