# Password-authenticated exchange dependency

`Sources/CCryptoBoringSSL` is copied without changes from Apple's swift-crypto
4.0.0 release: https://github.com/apple/swift-crypto/tree/4.0.0/Sources/CCryptoBoringSSL

BoringSSL revision: 0226f30467f540a3f62ef48d453f93927da199b6 (also in hash.txt).
MacPair uses its existing SPAKE2 implementation through a small Objective-C
wrapper. This is BoringSSL's SPAKE2 protocol variant, not a claim of RFC 9382
wire compatibility. MacPair performs explicit role-separated key confirmation
and uses independent directional AES-GCM keys derived with HKDF-SHA256.

The local Package.swift builds the C/C++ target as a static library with the
existing Xcode toolchain. It adds no downloaded Swift packages or runtime
requirements. Original source headers and the upstream LICENSE/NOTICE files
are retained. MacPair's integration has not received an independent security audit.
