//! macOS “open folder in Orbit” — Finder / `open -a Orbit.app /path` (VS Code, Cursor).
//! Linked only on macOS (see build.zig).

#import <Cocoa/Cocoa.h>
#include <string.h>
#include <stddef.h>

#define ORBIT_OPEN_CAP 8
#define ORBIT_PATH_MAX 4096

static char g_paths[ORBIT_OPEN_CAP][ORBIT_PATH_MAX];
static int g_head = 0;
static int g_count = 0;
static id g_handler = nil;

static void orbit_push_path(const char *path) {
    if (path == NULL || path[0] == 0 || g_count >= ORBIT_OPEN_CAP) return;
    const int idx = (g_head + g_count) % ORBIT_OPEN_CAP;
    strncpy(g_paths[idx], path, ORBIT_PATH_MAX - 1);
    g_paths[idx][ORBIT_PATH_MAX - 1] = 0;
    g_count += 1;
}

static void orbit_push_url(NSURL *url) {
    if (url == nil) return;
    NSString *path = url.path;
    if (path == nil || [path length] == 0) return;
    // Keep files as well as folders so Orbit can open a syntax-highlighted preview.
    orbit_push_path([path fileSystemRepresentation]);
}

@interface OrbitOpenHandler : NSObject
- (void)handleOpenDocs:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply;
@end

@implementation OrbitOpenHandler
- (void)handleOpenDocs:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    (void)reply;
    NSAppleEventDescriptor *list = [event paramDescriptorForKeyword:keyDirectObject];
    if (list == nil) return;
    const NSInteger n = [list numberOfItems];
    for (NSInteger i = 1; i <= n; i++) {
        NSAppleEventDescriptor *item = [list descriptorAtIndex:i];
        if (item == nil) continue;
        NSURL *url = nil;
        if ([item respondsToSelector:@selector(fileURLValue)]) {
            url = [item fileURLValue];
        }
        if (url == nil) {
            NSAppleEventDescriptor *as_url = [item coerceToDescriptorType:typeFileURL];
            NSString *s = [as_url stringValue];
            if (s != nil) url = [NSURL URLWithString:s];
        }
        if (url == nil) {
            NSString *s = [item stringValue];
            if (s != nil) url = [NSURL fileURLWithPath:s];
        }
        orbit_push_url(url);
    }
}
@end

void orbit_macos_install_open_handler(void) {
    @autoreleasepool {
        if (g_handler == nil) {
            g_handler = [[OrbitOpenHandler alloc] init];
        }
        [[NSAppleEventManager sharedAppleEventManager]
            setEventHandler:g_handler
            andSelector:@selector(handleOpenDocs:withReplyEvent:)
            forEventClass:kCoreEventClass
            andEventID:kAEOpenDocuments];
    }
}

int orbit_macos_take_open_path(char *out, size_t cap) {
    if (out == NULL || cap == 0 || g_count <= 0) return 0;
    strncpy(out, g_paths[g_head], cap - 1);
    out[cap - 1] = 0;
    g_head = (g_head + 1) % ORBIT_OPEN_CAP;
    g_count -= 1;
    return (int)strlen(out);
}
