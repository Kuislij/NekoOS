#include <pango/pangocairo.h>
#include <fontconfig/fontconfig.h>
#include <stdio.h>
#include <stdint.h>

int main(int argc, char **argv)
{
    const char *output = argc > 1 ? argv[1] : "/tmp/neko-pango-smoke.png";
    if (!FcInit()) {
        fputs("Pango could not initialize packaged Fontconfig configuration\n", stderr);
        return 1;
    }
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 320, 160);
    cairo_t *cr = cairo_create(surface);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    PangoLayout *layout = pango_cairo_create_layout(cr);
    PangoFontDescription *font = pango_font_description_from_string("DejaVu Sans 16");
    pango_layout_set_font_description(layout, font);
    pango_layout_set_width(layout, 280 * PANGO_SCALE);
    pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
    pango_layout_set_text(layout, "NekoOS office\n\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82 "
                          "\xd7\xa9\xd7\x9c\xd7\x95\xd7\x9d "
                          "\xd8\xb3\xd9\x84\xd8\xa7\xd9\x85", -1);
    int width, height;
    pango_layout_get_pixel_size(layout, &width, &height);
    int ok = width > 0 && width <= 280 && height > 20 && height <= 150 &&
             pango_layout_get_line_count(layout) >= 2 &&
             pango_layout_get_unknown_glyphs_count(layout) == 0;
    cairo_move_to(cr, 10, 10);
    cairo_set_source_rgb(cr, 0, 0, 0);
    pango_cairo_show_layout(cr, layout);
    cairo_surface_flush(surface);
    unsigned ink_pixels = 0;
    const unsigned char *data = cairo_image_surface_get_data(surface);
    int stride = cairo_image_surface_get_stride(surface);
    for (int y = 0; y < 160; ++y) {
        const uint32_t *row = (const uint32_t *)(data + y * stride);
        for (int x = 0; x < 320; ++x)
            if ((row[x] & 0x00ffffff) != 0x00ffffff) ++ink_pixels;
    }
    ok = ok && ink_pixels > 100 && cairo_status(cr) == CAIRO_STATUS_SUCCESS &&
         cairo_surface_write_to_png(surface, output) == CAIRO_STATUS_SUCCESS;
    pango_font_description_free(font);
    g_object_unref(layout);
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    if (!ok) {
        fprintf(stderr, "Pango multilingual layout/render failed: %dx%d, ink=%u\n", width, height, ink_pixels);
        return 1;
    }
    puts("PANGO_SMOKE_OK");
    return 0;
}
