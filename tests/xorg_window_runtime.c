/* An independent Xlib client for the real Xorg display and input smoke test. */
#include <X11/Xlib.h>
#include <X11/keysym.h>

#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int check_input(Display *display, Window window)
{
    struct timespec now;
    time_t deadline;
    int key_seen = 0;
    int button_seen = 0;

    XSelectInput(display, window, KeyPressMask | ButtonPressMask |
                                PointerMotionMask);
    XSetInputFocus(display, window, RevertToPointerRoot, CurrentTime);
    if (XGrabKeyboard(display, window, False, GrabModeAsync, GrabModeAsync,
                      CurrentTime) != GrabSuccess ||
        XGrabPointer(display, window, False, PointerMotionMask |
                     ButtonPressMask, GrabModeAsync, GrabModeAsync, None, None,
                     CurrentTime) != GrabSuccess) {
        fputs("Xorg could not grab keyboard and pointer\n", stderr);
        return 1;
    }
    XSync(display, False);
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
    }
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        perror("clock_gettime");
        return 1;
    }
    deadline = now.tv_sec + 30;
    puts("XORG_INPUT_CLIENT_READY");
    fflush(stdout);
    while (!key_seen || !button_seen) {
        struct pollfd connection = { ConnectionNumber(display), POLLIN, 0 };
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 ||
            now.tv_sec >= deadline) {
            fputs("Xorg input events timed out\n", stderr);
            return 1;
        }
        if (poll(&connection, 1, 1000) < 0) {
            perror("poll");
            return 1;
        }
        while (XPending(display)) {
            XEvent event;
            XNextEvent(display, &event);
            if (!key_seen && event.type == KeyPress &&
                XLookupKeysym(&event.xkey, 0) == XK_a) {
                puts("XORG_KEY_EVENT_READY");
                fflush(stdout);
                key_seen = 1;
            }
            if (!button_seen && event.type == ButtonPress &&
                event.xbutton.button == Button1) {
                puts("XORG_MOUSE_EVENT_READY");
                fflush(stdout);
                button_seen = 1;
            }
        }
    }
    puts("XORG_CLIENT_INPUT_READY");
    return 0;
}

int main(int argc, char **argv)
{
    Display *display = XOpenDisplay(NULL);
    XWindowAttributes attributes;
    Window window;
    int input_check = argc == 2 && strcmp(argv[1], "--input") == 0;
    int status = 0;

    if (argc > 2 || (argc == 2 && !input_check)) {
        fputs("usage: neko-xorg-window-check [--input]\n", stderr);
        return 2;
    }

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
    fflush(stdout);
    if (input_check)
        status = check_input(display, window);
    XDestroyWindow(display, window);
    XCloseDisplay(display);
    return status;
}
