# Third-party notices

Sources/CGVirtualDisplayPrivate.h is copied without modification from OpenDisplay:

- Project: https://github.com/peetzweg/opendisplay
- Source: https://github.com/peetzweg/opendisplay/blob/main/Mac/CGVirtualDisplayPrivate.h
- Original Git blob SHA: cd14f91578f713f4e4d42ca57679ee4697965714
- License: GNU General Public License version 3. The complete license is included in LICENSE.
- Its original comment attributes the reverse-engineered interface to Khaos Tian's VirtualDisplayExp. That comment is preserved.

Sources/VirtualScreen.swift follows OpenDisplay's approach to CGVirtualDisplay but implements a small fixed-resolution, session-only arrangement for MacPair. The networking, video pipeline, app UI, localization, session control and tests were written for this project. The combined project is provided under GPL-3.0-only.

MacPair is an independent experimental prototype, not endorsed by OpenDisplay or OpenAirDisplay. It includes none of their updater, cloud, signing or service configurations.
