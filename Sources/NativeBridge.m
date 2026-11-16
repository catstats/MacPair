// SPDX-License-Identifier: GPL-3.0-only
#import "NativeBridge.h"
#import "CGVirtualDisplayPrivate.h"

@implementation MPVirtualScreen {
    CGVirtualDisplay *_display;
}
- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height {
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
        descriptor.maxPixelsWide = (unsigned int)width;
        descriptor.maxPixelsHigh = (unsigned int)height;
        descriptor.sizeInMillimeters = CGSizeMake(width * 25.4 / 110.0, height * 25.4 / 110.0);
        descriptor.vendorID = 0x4D50;
        descriptor.productID = 0x0001;
        descriptor.serialNum = 0x4D500001;
        _display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!_display) return nil;
        CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = 0;
        settings.modes = @[[[modeClass alloc] initWithWidth:width height:height refreshRate:60]];
        if (![_display applySettings:settings]) return nil;
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
