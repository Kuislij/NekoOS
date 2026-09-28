/* Guest smoke test for the packaged server-side graphics libraries. */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>

struct library_symbol {
    const char *library;
    const char *symbol;
};

int main(void)
{
    static const struct library_symbol required[] = {
        {"libxkbfile.so.1", "XkbAccessXDetailText"},
        {"libfontenc.so.1", "FontEncFind"},
        {"libXfont2.so.2", "FontFileRegisterFpeFunctions"},
        {"libxcvt.so.0", "libxcvt_gen_mode_info"},
        {"libpciaccess.so.0", "pci_system_init"},
        {"libdrm.so.2", "drmGetDevices2"},
    };
    const char message[] = "NekoOS Xorg prerequisites";
    unsigned char compressed[128];
    unsigned char restored[128];
    uLongf compressed_len = sizeof compressed;
    uLongf restored_len = sizeof restored;
    size_t index;

    if (strncmp(zlibVersion(), ZLIB_VERSION, 5) != 0 ||
        compress2(compressed, &compressed_len,
                  (const unsigned char *)message, sizeof message, 6) != Z_OK ||
        uncompress(restored, &restored_len, compressed, compressed_len) != Z_OK ||
        restored_len != sizeof message ||
        memcmp(restored, message, sizeof message) != 0) {
        fputs("zlib round trip failed\n", stderr);
        return 1;
    }
    for (index = 0; index < sizeof required / sizeof required[0]; ++index) {
        void *handle = dlopen(required[index].library, RTLD_NOW | RTLD_LOCAL);
        if (handle == NULL || dlsym(handle, required[index].symbol) == NULL) {
            fprintf(stderr, "cannot load %s: %s\n", required[index].library,
                    dlerror());
            return 1;
        }
        dlclose(handle);
    }
    puts("XORG_STACK_RUNTIME_READY");
    return 0;
}
