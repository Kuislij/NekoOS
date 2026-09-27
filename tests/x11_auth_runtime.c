/* Guest-side dynamic-link and runtime probe for both X11 base libraries. */
#include <X11/Xauth.h>
#include <X11/Xdmcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    ARRAY8 bytes = {0};
    const char *authority = "/tmp/neko-xauth-probe";
    if (setenv("XAUTHORITY", authority, 1) != 0 ||
        XauFileName() == NULL || strcmp(XauFileName(), authority) != 0) {
        return 1;
    }
    if (!XdmcpAllocARRAY8(&bytes, 4) || bytes.length != 4 || bytes.data == NULL) {
        return 1;
    }
    bytes.data[0] = 42;
    if (bytes.data[0] != 42) {
        XdmcpDisposeARRAY8(&bytes);
        return 1;
    }
    XdmcpDisposeARRAY8(&bytes);
    puts("X11_BASE_RUNTIME_READY");
    return 0;
}
