fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios sync_certificates

```sh
[bundle exec] fastlane ios sync_certificates
```

Sync certificates and profiles from git repo

### ios certificates_new

```sh
[bundle exec] fastlane ios certificates_new
```

Generate new certificates (run once for new team members)

### ios install_pods

```sh
[bundle exec] fastlane ios install_pods
```

Install CocoaPods dependencies

### ios bump_build_number

```sh
[bundle exec] fastlane ios bump_build_number
```

Bump build number based on latest TestFlight build

### ios build_ios

```sh
[bundle exec] fastlane ios build_ios
```

Build iOS app for TestFlight

### ios upload_testflight

```sh
[bundle exec] fastlane ios upload_testflight
```

Upload to TestFlight

### ios deploy_testflight

```sh
[bundle exec] fastlane ios deploy_testflight
```

Deploy to TestFlight (full pipeline)

### ios deploy_production

```sh
[bundle exec] fastlane ios deploy_production
```

Deploy to App Store (production)

### ios add_device

```sh
[bundle exec] fastlane ios add_device
```

Add new device and refresh provisioning profiles

### ios screenshots_native

```sh
[bundle exec] fastlane ios screenshots_native
```

Take screenshots for App Store (native Xcode UI tests)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Take screenshots using Flutter integration tests

### ios screenshot_device

```sh
[bundle exec] fastlane ios screenshot_device
```

Take screenshots on a single device

### ios frame_screenshots

```sh
[bundle exec] fastlane ios frame_screenshots
```

Add device frames to screenshots

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload screenshots to App Store Connect

### ios screenshots_full

```sh
[bundle exec] fastlane ios screenshots_full
```

Full screenshot pipeline: capture, frame, and upload

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

Create app on App Store Connect

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
