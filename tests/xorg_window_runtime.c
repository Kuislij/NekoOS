/* An independent Xlib client for the first real Xorg display smoke test. */
#include <X11/Xlib.h>

#include <stdio.h>

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    XWindowAttributes attributes;
    Window window;

    if (display == NULL) {
        fputs("cannot connect to Xorg display\n", stderr);
        return 1;
    }
    window = XCreateSimpleWindow(display, DefaultRootWindow(display),
                                 40, 40, 320, 180, 1,
                                 BlackPixel(display, DefaultScreen(display)),
                                 WhitePixel(display, DefaultScreen(display)));
    XStoreName(display, window, "NekoOS Xorg smoke test");
    XMapWindow(display, window);
    XSync(display, False);
    if (!XGetWindowAttributes(display, window, &attributes) ||
        attributes.map_state != IsViewable) {
        fputs("Xorg did not map the client window\n", stderr);
        XDestroyWindow(display, window);
        XCloseDisplay(display);
        return 1;
    }
    puts("XORG_CLIENT_READY");
    XDestroyWindow(display, window);
    XCloseDisplay(display);
    return 0;
}
