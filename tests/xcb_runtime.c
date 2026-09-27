/* Guest-side libxcb loader probe; no X server is needed. */
#include <xcb/xcb.h>

#include <stdio.h>
#include <stdlib.h>

int main(void)
{
    char *host = NULL;
    int display = -1;
    int screen = -1;

    if (!xcb_parse_display(":42.1", &host, &display, &screen) ||
        display != 42 || screen != 1) {
        free(host);
        return 1;
    }
    free(host);
    puts("XCB_RUNTIME_READY");
    return 0;
}
