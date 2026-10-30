# Bundled USB libraries

The application dynamically links universal `arm64` / `x86_64` builds of libmtp 1.1.23 and libusb 1.0.30. Both slices require macOS 14 or later.

- libmtp source: https://github.com/libmtp/libmtp/tree/v1.1.23
- libusb source: https://github.com/libusb/libusb/tree/v1.0.30
- Licenses: `licenses/libmtp-LGPL.txt` and `licenses/libusb-LGPL.txt` (LGPL 2.1 or later).

Release assets include the corresponding upstream source archives. These libraries are unmodified upstream source builds; their Mach-O install names use `@rpath` and `@loader_path` so they can load from the app bundle. Build each source for `arm64` and `x86_64` with `MACOSX_DEPLOYMENT_TARGET=14.0`, combine matching libraries with `lipo -create`, and keep libmtp’s libusb dependency relative to `@loader_path/libusb-1.0.0.dylib`.

To use a modified library, build it with compatible exported symbols and architectures, replace the matching file in `Nearby Drop.app/Contents/Frameworks`, then ad hoc sign the changed libraries and app. Make a copy first. The app disables hardened-runtime library validation to permit replacement. LGPL rights, including modification and reverse engineering for debugging those modifications, are retained.
