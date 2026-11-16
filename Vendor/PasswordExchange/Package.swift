// swift-tools-version:6.0
import PackageDescription

// Build only Apple's vendored C/C++ implementation. No remote package or
// additional runtime installation is needed on either Mac.
let package = Package(
    name: "MacPairCrypto",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MacPairCrypto", type: .static, targets: ["CCryptoBoringSSL"])],
    targets: [.target(
        name: "CCryptoBoringSSL",
        exclude: ["hash.txt", "CMakeLists.txt", "PrivacyInfo.xcprivacy",
                  "crypto/bio/connect.cc", "crypto/bio/socket_helper.cc", "crypto/bio/socket.cc"]
    )],
    cxxLanguageStandard: .cxx17
)
