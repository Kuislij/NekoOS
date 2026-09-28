/* Independent X11 client proving a window manager re-parents new windows. */
#define _POSIX_C_SOURCE 200809L
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int check_manager_identity(Display *display, Window root)
{
    Atom check = XInternAtom(display, "_NET_SUPPORTING_WM_CHECK", False);
    Atom name = XInternAtom(display, "_NET_WM_NAME", False);
    Atom actual;
    int format;
    unsigned long count, remaining;
    unsigned char *value = NULL;
    Window manager;

    if (XGetWindowProperty(display, root, check, 0, 1, False, XA_WINDOW,
                           &actual, &format, &count, &remaining, &value) != Success ||
        actual != XA_WINDOW || format != 32 || count != 1 || !value) {
        fprintf(stderr, "evilwm did not advertise a window manager\n");
        if (value)
            XFree(value);
        return 0;
    }
    manager = *(Window *)value;
    XFree(value);
    value = NULL;
    if (XGetWindowProperty(display, manager, name, 0, 16, False, XA_STRING,
                           &actual, &format, &count, &remaining, &value) != Success ||
        actual != XA_STRING || format != 8 || count != 6 || !value ||
        memcmp(value, "evilwm", 6) != 0) {
        fprintf(stderr, "unexpected window manager identity\n");
        if (value)
            XFree(value);
        return 0;
    }
    XFree(value);
    return 1;
}

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    Window root, client, parent, ignored;
    Window *children = NULL;
    unsigned int child_count;
    XWindowAttributes attrs;
    struct timespec pause = {0, 50000000};
    int managed = 0;

    if (!display) {
        fprintf(stderr, "cannot open X display\n");
        return 1;
    }
    root = DefaultRootWindow(display);
    if (!check_manager_identity(display, root)) {
        XCloseDisplay(display);
        return 1;
    }

    client = XCreateSimpleWindow(display, root, 40, 40, 240, 120, 0, 0, 0);
    XStoreName(display, client, "NekoOS evilwm integration check");
    XMapWindow(display, client);
    XSync(display, False);
    for (int attempt = 0; attempt < 40; attempt++) {
        if (XQueryTree(display, client, &ignored, &parent,
                       &children, &child_count) == 0)
            break;
        if (children)
            XFree(children);
        children = NULL;
        if (parent != root &&
            XGetWindowAttributes(display, client, &attrs) != 0 &&
            attrs.map_state == IsViewable) {
            managed = 1;
            break;
        }
        nanosleep(&pause, NULL);
    }
    XDestroyWindow(display, client);
    XCloseDisplay(display);
    if (!managed) {
        fprintf(stderr, "evilwm did not re-parent and show the X11 client\n");
        return 1;
    }
    puts("EVILWM_CLIENT_MANAGED");
    return 0;
}
