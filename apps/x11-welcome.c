/* A small persistent X11 client for the opt-in window-managed session. */
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

#include <stdio.h>
#include <string.h>

static unsigned long color(Display *display, const char *name,
                           unsigned long fallback)
{
    XColor exact, visible;
    if (XAllocNamedColor(display, DefaultColormap(display,
                                                  DefaultScreen(display)),
                         name, &visible, &exact))
        return visible.pixel;
    return fallback;
}

static void label(Display *display, Window window, GC gc,
                  int x, int y, const char *text)
{
    XDrawString(display, window, gc, x, y, text, (int)strlen(text));
}

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    Window window;
    GC gc;
    XEvent event;
    Atom delete_window;
    XFontStruct *font;
    unsigned long background, foreground, accent, button;
    int running = 1, destroyed = 0;

    if (!display) {
        fputs("neko-x11-welcome: cannot connect to X display\n", stderr);
        return 1;
    }
    background = color(display, "#f3f7fb", WhitePixel(display,
                                                       DefaultScreen(display)));
    foreground = color(display, "#192b3c", BlackPixel(display,
                                                       DefaultScreen(display)));
    accent = color(display, "#2870a8", foreground);
    button = color(display, "#d9e8f3", background);
    window = XCreateSimpleWindow(display, DefaultRootWindow(display),
                                 96, 90, 480, 280, 2, accent, background);
    XStoreName(display, window, "NekoOS - X11 session");
    XSelectInput(display, window, ExposureMask | KeyPressMask |
                                ButtonPressMask | StructureNotifyMask);
    delete_window = XInternAtom(display, "WM_DELETE_WINDOW", False);
    XSetWMProtocols(display, window, &delete_window, 1);
    gc = XCreateGC(display, window, 0, NULL);
    font = XLoadQueryFont(display, "fixed");
    if (font)
        XSetFont(display, gc, font->fid);
    XMapWindow(display, window);
    XFlush(display);

    while (running) {
        XNextEvent(display, &event);
        switch (event.type) {
        case Expose:
            if (event.xexpose.count != 0)
                break;
            XSetForeground(display, gc, background);
            XFillRectangle(display, window, gc, 0, 0, 480, 280);
            XSetForeground(display, gc, accent);
            XFillRectangle(display, window, gc, 0, 0, 480, 48);
            XSetForeground(display, gc, WhitePixel(display,
                                                   DefaultScreen(display)));
            label(display, window, gc, 22, 29, "NekoOS");
            XSetForeground(display, gc, foreground);
            label(display, window, gc, 22, 86, "A real X11 windowed session is running.");
            label(display, window, gc, 22, 112, "Xorg draws this window; a separate window manager");
            label(display, window, gc, 22, 130, "controls its position and border.");
            label(display, window, gc, 22, 167, "Xfce and Thunar are the next desktop milestone.");
            XSetForeground(display, gc, button);
            XFillRectangle(display, window, gc, 22, 201, 114, 34);
            XSetForeground(display, gc, foreground);
            label(display, window, gc, 58, 223, "Close");
            label(display, window, gc, 22, 259, "Click Close or press Q to leave this window.");
            break;
        case ButtonPress:
            if (event.xbutton.button == Button1 &&
                event.xbutton.x >= 22 && event.xbutton.x < 136 &&
                event.xbutton.y >= 201 && event.xbutton.y < 235)
                running = 0;
            break;
        case KeyPress:
            if (XLookupKeysym(&event.xkey, 0) == XK_q ||
                XLookupKeysym(&event.xkey, 0) == XK_Escape)
                running = 0;
            break;
        case ClientMessage:
            if ((Atom)event.xclient.data.l[0] == delete_window)
                running = 0;
            break;
        case DestroyNotify:
            destroyed = 1;
            running = 0;
            break;
        default:
            break;
        }
    }
    if (font)
        XFreeFont(display, font);
    XFreeGC(display, gc);
    if (!destroyed)
        XDestroyWindow(display, window);
    XCloseDisplay(display);
    return 0;
}
