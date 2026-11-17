# Third-party software

FourGSwitch application code is MIT licensed. No source from other DJI applications is included.

## DJOneHub reference and acknowledgement

We acknowledge the authors and contributors of [DJOneHub / DJOneHub-mac-enhanced](https://github.com/rogerbush007-a11y/DJOneHub-mac-enhanced)
for their published work on the first-generation DJI 4G module. The implementation and documentation were
cross-checked at commit `5b15eaec0e97dd9fa7b2abe54d0d1289c1e93054`.

References cover the documented USB identity and network modes, libusb-based AT communication and
AT/OK probing, and re-reading actual configuration after USB re-enumeration. FourGSwitch implements
its own focused switching application, state coordinator, native interfaces and build pipeline.
The [README relationship section](../README.md#与-djonehub-的关系及本项目的改进) records the specific references,
changes and limitations. This acknowledgement describes protocol and workflow references, not a code merge,
runtime dependency, endorsement or upstream performance comparison.

DJOneHub's root [license](https://github.com/rogerbush007-a11y/DJOneHub-mac-enhanced/blob/5b15eaec0e97dd9fa7b2abe54d0d1289c1e93054/LICENSE)
is PolyForm Noncommercial 1.0.0. Its source is not copied, linked or bundled in FourGSwitch, and
FourGSwitch's MIT license does not relicense any DJOneHub code. No DJOneHub service, module-side agent,
voice runtime, media asset or proprietary driver is distributed with this application.

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
