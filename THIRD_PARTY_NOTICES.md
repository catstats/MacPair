# Third-party notices

Sources/CGVirtualDisplayPrivate.h is copied without modification from OpenDisplay:

- Project: https://github.com/peetzweg/opendisplay
- Source: https://github.com/peetzweg/opendisplay/blob/main/Mac/CGVirtualDisplayPrivate.h
- Original Git blob SHA: cd14f91578f713f4e4d42ca57679ee4697965714
- License: GNU General Public License version 3. The complete license is included in LICENSE.
- Its original comment attributes the reverse-engineered interface to Khaos Tian's VirtualDisplayExp. That comment is preserved.

Sources/VirtualScreen.swift follows OpenDisplay's approach to CGVirtualDisplay but implements a small Retina-aware, session-only arrangement for MacPair. The networking, video pipeline, app UI, localization, session control and tests were written for this project. The combined project is provided under GPL-3.0-only.

MacPair is an independent experimental prototype, not endorsed by OpenDisplay or OpenAirDisplay. It includes none of their updater, cloud, signing or service configurations.

## Password-authenticated pairing

Vendor/PasswordExchange/Sources/CCryptoBoringSSL is retained from Apple swift-crypto 4.0.0. Its BoringSSL revision is 0226f30467f540a3f62ef48d453f93927da199b6. Original C/C++ source headers are unmodified. A local Package.swift builds the C target as a static library; Sources/NativeBridge.m wraps its existing SPAKE2 interface.

- Source: https://github.com/apple/swift-crypto/tree/4.0.0/Sources/CCryptoBoringSSL
- Apple license/notice: Vendor/PasswordExchange/LICENSE.txt and NOTICE.txt.
- BoringSSL component license: Vendor/PasswordExchange/license/BoringSSL-LICENSE.txt, copied from the exact revision.
- These notices are also included in the built app's Resources.

The pairing integration and tests are MacPair-specific; no independent security audit is claimed.
