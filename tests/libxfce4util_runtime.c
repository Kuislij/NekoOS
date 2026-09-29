/* Exercise the first packaged Xfce library inside the guest. */
#include <libxfce4util/libxfce4util.h>
#include <stdio.h>

int main(void)
{
    if (g_strcmp0(xfce_version_string(), "4.20") != 0) {
        fputs("Unexpected Xfce library version\n", stderr);
        return 1;
    }
    gchar *result = xfce_str_replace("cat", "a", "o");
    if (g_strcmp0(result, "cot") != 0) {
        g_free(result);
        fputs("Xfce string replacement failed\n", stderr);
        return 1;
    }
    g_free(result);
    puts("LIBXFCE4UTIL_RUNTIME_READY");
    return 0;
}
