/* Guest-side libXext loader probe, independent of a running X server. */
#include <X11/Xlib.h>
#include <X11/extensions/Xext.h>

#include <stdio.h>

static int probe_error_handler(Display *display, const char *name, const char *reason)
{
    (void)display;
    (void)name;
    (void)reason;
    return 0;
}

int main(void)
{
    XextErrorHandler previous = XSetExtensionErrorHandler(probe_error_handler);
    if (XSetExtensionErrorHandler(previous) != probe_error_handler) {
        return 1;
    }
    puts("XEXT_RUNTIME_READY");
    return 0;
}
