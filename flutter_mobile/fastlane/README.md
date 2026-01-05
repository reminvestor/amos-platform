fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### install_flutter_deps

```sh
[bundle exec] fastlane install_flutter_deps
```

Install Flutter dependencies

### test

```sh
[bundle exec] fastlane test
```

Run Flutter tests

### analyze

```sh
[bundle exec] fastlane analyze
```

Analyze Flutter code

### build_all

```sh
[bundle exec] fastlane build_all
```

Build both iOS and Android

### deploy_all_internal

```sh
[bundle exec] fastlane deploy_all_internal
```

Deploy to both TestFlight and Play Store Internal

### clean

```sh
[bundle exec] fastlane clean
```

Clean build artifacts

### setup

```sh
[bundle exec] fastlane setup
```

Setup development environment

### generate_code

```sh
[bundle exec] fastlane generate_code
```

Generate code (freezed, json_serializable, etc.)

### generate_watch

```sh
[bundle exec] fastlane generate_watch
```

Watch for code generation

### bump_version

```sh
[bundle exec] fastlane bump_version
```

Bump version number

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
