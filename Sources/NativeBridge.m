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
