/* Exercise real GTK image operations without an X server or loader cache. */
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>
#include <string.h>

static int fail(const char *operation, GError *error)
{
    fprintf(stderr, "GDK_PIXBUF_SMOKE_FAILED: %s: %s\n", operation,
            error ? error->message : "unexpected pixel data");
    g_clear_error(&error);
    return 1;
}

static gboolean pixels_match(GdkPixbuf *pixbuf, int width, int height)
{
    const guchar expected[] = { 0x24, 0x68, 0xac, 0x80 };
    if (!pixbuf || gdk_pixbuf_get_width(pixbuf) != width ||
        gdk_pixbuf_get_height(pixbuf) != height ||
        !gdk_pixbuf_get_has_alpha(pixbuf) ||
        gdk_pixbuf_get_n_channels(pixbuf) != 4 ||
        gdk_pixbuf_get_bits_per_sample(pixbuf) != 8)
        return FALSE;
    for (int y = 0; y < height; ++y) {
        const guchar *row = gdk_pixbuf_get_pixels(pixbuf) +
                            y * gdk_pixbuf_get_rowstride(pixbuf);
        for (int x = 0; x < width; ++x)
            if (memcmp(row + x * 4, expected, sizeof expected) != 0)
                return FALSE;
    }
    return TRUE;
}

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/tmp/neko-gdk-pixbuf-smoke.png";
    const char *xpm_data[] = {
        "2 1 2 1", "R c #2468ac", ". c None", "R.", NULL
    };
    GError *error = NULL;
    GdkPixbuf *original = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 8, 6);
    if (!original)
        return fail("allocate", NULL);
    gdk_pixbuf_fill(original, 0x2468ac80);
    if (!gdk_pixbuf_save(original, path, "png", &error, NULL))
        return fail("save PNG", error);

    GdkPixbuf *loaded = gdk_pixbuf_new_from_file(path, &error);
    if (!loaded)
        return fail("load PNG by signature", error);
    if (!pixels_match(loaded, 8, 6))
        return fail("PNG round trip", NULL);
    GdkPixbuf *scaled = gdk_pixbuf_scale_simple(loaded, 4, 3, GDK_INTERP_NEAREST);
    if (!pixels_match(scaled, 4, 3))
        return fail("scale PNG", NULL);

    gchar *encoded = NULL;
    gsize length = 0;
    if (!gdk_pixbuf_save_to_buffer(scaled, &encoded, &length, "png", &error, NULL))
        return fail("encode PNG buffer", error);
    GdkPixbufLoader *loader = gdk_pixbuf_loader_new();
    for (gsize offset = 0; offset < length;) {
        const gsize chunk = MIN((gsize)7, length - offset);
        if (!gdk_pixbuf_loader_write(loader, (const guchar *)encoded + offset,
                                    chunk, &error))
            return fail("incremental PNG decoding", error);
        offset += chunk;
    }
    if (!gdk_pixbuf_loader_close(loader, &error))
        return fail("finish PNG decoding", error);
    if (!pixels_match(gdk_pixbuf_loader_get_pixbuf(loader), 4, 3))
        return fail("decoded PNG buffer", NULL);

    /* GTK3 still uses this legacy API, so verify it deliberately. */
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    GdkPixbuf *xpm = gdk_pixbuf_new_from_xpm_data(xpm_data);
    G_GNUC_END_IGNORE_DEPRECATIONS
    if (!xpm || gdk_pixbuf_get_width(xpm) != 2 ||
        !gdk_pixbuf_get_has_alpha(xpm))
        return fail("legacy XPM loading", NULL);
    const guchar *xp = gdk_pixbuf_get_pixels(xpm);
    if (xp[0] != 0x24 || xp[1] != 0x68 || xp[2] != 0xac ||
        xp[3] != 0xff || xp[7] != 0)
        return fail("XPM colors and transparency", NULL);

    g_object_unref(xpm);
    g_object_unref(loader);
    g_free(encoded);
    g_object_unref(scaled);
    g_object_unref(loaded);
    g_object_unref(original);
    puts("GDK_PIXBUF_SMOKE_OK: PNG file/buffer, RGBA, scaling and builtin XPM");
    return 0;
}
