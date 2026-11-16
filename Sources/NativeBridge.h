// SPDX-License-Identifier: GPL-3.0-only
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
@interface MPVirtualScreen : NSObject
@property(readonly) uint32_t displayID;
- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height scale:(NSUInteger)scale serial:(uint32_t)serial;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
