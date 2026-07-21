//! macOS Dock / app icon — set NSApplication icon from embedded PNG bytes.
//! Linked only on macOS (see build.zig).

#import <Cocoa/Cocoa.h>
#include <stddef.h>
#include <stdint.h>

void orbit_set_dock_icon_png(const uint8_t *data, size_t len) {
    if (data == NULL || len == 0) return;
    @autoreleasepool {
        NSData *nsdata = [NSData dataWithBytes:data length:len];
        NSImage *img = [[NSImage alloc] initWithData:nsdata];
        if (img == nil) return;
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app setApplicationIconImage:img];
    }
}
