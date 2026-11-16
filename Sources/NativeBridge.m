// SPDX-License-Identifier: GPL-3.0-only
#import "NativeBridge.h"
#import "CGVirtualDisplayPrivate.h"

@implementation MPVirtualScreen {
    CGVirtualDisplay *_display;
}
- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height scale:(NSUInteger)scale serial:(uint32_t)serial {
    self = [super init];
    if (!self) return nil;
    // Look up private classes dynamically, and contain Objective-C exceptions
    // here instead of letting them cross into Swift.
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptorClass || !displayClass || !settingsClass || !modeClass) return nil;
    @try {
        CGVirtualDisplayDescriptor *descriptor = [[descriptorClass alloc] init];
        [descriptor setDispatchQueue:dispatch_get_main_queue()];
        descriptor.name = @"MacPair";
        descriptor.maxPixelsWide = (unsigned int)(width * scale);
        descriptor.maxPixelsHigh = (unsigned int)(height * scale);
        descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 110.0, height * 25.4 / 110.0);
        descriptor.vendorID = 0x4D50;
        descriptor.productID = 0x0001;
        descriptor.serialNum = serial;
        _display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!_display) { NSLog(@"MacPair: CGVirtualDisplay descriptor rejected (%lux%lu @%lu, serial %u)", width, height, scale, serial); return nil; }
        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = scale == 2 ? 1 : 0;
        settings.modes = @[[[modeClass alloc] initWithWidth:width height:height refreshRate:60]];
        if (![_display applySettings:settings]) { NSLog(@"MacPair: CGVirtualDisplay settings rejected (%lux%lu @%lu, id %u)", width, height, scale, _display.displayID); return nil; }
        return self;
    } @catch (NSException *exception) {
        NSLog(@"MacPair virtual display: %@", exception.reason);
        return nil;
    }
}
- (uint32_t)displayID { return _display.displayID; }
- (void)invalidate {
    @autoreleasepool { _display = nil; }
}
@end

#import "CCryptoBoringSSL_curve25519.h"
#import "CCryptoBoringSSL_mem.h"

@implementation MPPasswordExchange {
    SPAKE2_CTX *_context;
    NSData *_message;
}
- (nullable instancetype)initWithHost:(BOOL)host secret:(NSData *)secret hostID:(NSString *)hostID displayID:(NSString *)displayID {
    self = [super init];
    if (!self) return nil;
    __attribute__((objc_precise_lifetime)) NSString *hostIdentity = [@"MacPair/v3/host/" stringByAppendingString:hostID];
    __attribute__((objc_precise_lifetime)) NSString *displayIdentity = [@"MacPair/v3/display/" stringByAppendingString:displayID];
    const char *hostName = hostIdentity.UTF8String;
    const char *displayName = displayIdentity.UTF8String;
    const char *mine = host ? hostName : displayName;
    const char *theirs = host ? displayName : hostName;
    _context = SPAKE2_CTX_new(host ? spake2_role_alice : spake2_role_bob,
        (const uint8_t *)mine, strlen(mine), (const uint8_t *)theirs, strlen(theirs));
    if (!_context) return nil;
    uint8_t output[SPAKE2_MAX_MSG_SIZE];
    size_t size = 0;
    if (!SPAKE2_generate_msg(_context, output, &size, sizeof(output), secret.bytes, secret.length)) return nil;
    _message = [NSData dataWithBytes:output length:size];
    OPENSSL_cleanse(output, sizeof(output));
    return self;
}
- (NSData *)message { return _message; }
- (nullable NSData *)sharedKeyForMessage:(NSData *)message {
    if (!_context || message.length != SPAKE2_MAX_MSG_SIZE) return nil;
    uint8_t key[SPAKE2_MAX_KEY_SIZE];
    size_t size = 0;
    int ok = SPAKE2_process_msg(_context, key, &size, sizeof(key), message.bytes, message.length);
    SPAKE2_CTX_free(_context);
    _context = NULL;
    NSData *result = ok && size == SPAKE2_MAX_KEY_SIZE ? [NSData dataWithBytes:key length:size] : nil;
    OPENSSL_cleanse(key, sizeof(key));
    return result;
}
- (void)dealloc { SPAKE2_CTX_free(_context); }
@end
