# Third-party software

FourGSwitch application code is MIT licensed. No source from other DJI applications is included.

## libusb 1.0.29 (macOS)

The macOS app dynamically links an unmodified libusb, licensed under LGPL-2.1-or-later.
Upstream: https://github.com/libusb/libusb/tree/v1.0.29

Each distributed macOS app includes the complete corresponding upstream source archive and COPYING in
`Contents/Resources/ThirdParty/`. The version and SHA-256 are pinned in `libusb.json`.
The build and relinking procedure is in `scripts/build-libusb.sh` and `scripts/package-macos.sh`.
You may modify and replace the bundled library; reverse engineering to debug modifications to it is permitted.
After replacement, re-sign the library and app locally, because any modification invalidates an existing code signature.
No Apple security setting needs to be disabled.

## .NET (Windows)

Windows packages bundle the Microsoft .NET desktop runtime and System.IO.Ports 10.0.0.
They are distributed under their upstream MIT licenses and third-party notices:
https://github.com/dotnet/runtime/blob/v10.0.0/LICENSE.TXT
https://github.com/dotnet/runtime/blob/v10.0.0/THIRD-PARTY-NOTICES.TXT
https://github.com/dotnet/wpf/blob/v10.0.0/LICENSE.TXT

Proprietary Quectel/DJI drivers are not included.
