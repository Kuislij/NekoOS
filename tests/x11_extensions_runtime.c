/* Check that the running server and packaged X11 extension libraries agree. */
#include <X11/Xlib.h>
#include <X11/extensions/Xfixes.h>
#include <X11/extensions/Xrandr.h>
#include <X11/extensions/Xrender.h>

#include <stdio.h>

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    int major = 0, minor = 0;

    if (!display) {
        fputs("cannot connect to X11 display\n", stderr);
        return 1;
    }
    if (!XRenderQueryVersion(display, &major, &minor)) {
        fputs("XRender extension is missing\n", stderr);
        XCloseDisplay(display);
        return 1;
    }
    printf("XRENDER_READY: %d.%d\n", major, minor);
    if (!XFixesQueryVersion(display, &major, &minor)) {
        fputs("XFixes extension is missing\n", stderr);
        XCloseDisplay(display);
        return 1;
    }
    printf("XFIXES_READY: %d.%d\n", major, minor);
    if (!XRRQueryVersion(display, &major, &minor)) {
        fputs("RandR extension is missing\n", stderr);
        XCloseDisplay(display);
        return 1;
    }
    printf("XRANDR_READY: %d.%d\n", major, minor);
    XCloseDisplay(display);
    return 0;
}
