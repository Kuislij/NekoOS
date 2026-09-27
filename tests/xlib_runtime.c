/* Guest-side Xlib probe; no X server is needed yet. */
#include <X11/Xlib.h>
#include <X11/keysym.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *name = XKeysymToString(XK_Return);
    if (XStringToKeysym("Return") != XK_Return || name == NULL ||
        strcmp(name, "Return") != 0 ||
        strcmp(XDisplayName(":42.1"), ":42.1") != 0) {
        return 1;
    }
    puts("XLIB_RUNTIME_READY");
    return 0;
}
