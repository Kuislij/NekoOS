#include <cairo.h>
#include <cairo-gobject.h>
#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    if (argc != 2)
        return 2;

    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 16, 16);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS)
        return 3;

    cairo_t *cr = cairo_create(surface);
    cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 1.0, 0.0, 0.0);
    cairo_rectangle(cr, 4.0, 4.0, 8.0, 8.0);
    cairo_fill(cr);
    if (cairo_status(cr) != CAIRO_STATUS_SUCCESS)
        return 4;
    cairo_destroy(cr);

    if (cairo_surface_write_to_png(surface, argv[1]) != CAIRO_STATUS_SUCCESS)
        return 5;
    cairo_surface_destroy(surface);

    surface = cairo_image_surface_create_from_png(argv[1]);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS ||
        cairo_image_surface_get_width(surface) != 16 ||
        cairo_image_surface_get_height(surface) != 16)
        return 6;

    unsigned char *data = cairo_image_surface_get_data(surface);
    int stride = cairo_image_surface_get_stride(surface);
    uint32_t center = ((uint32_t *)(data + 8 * stride))[8];
    uint32_t corner = ((uint32_t *)data)[0];
    cairo_surface_destroy(surface);
    if (center != 0xffff0000U || corner != 0xffffffffU)
        return 7;
    if (CAIRO_GOBJECT_TYPE_SURFACE == 0)
        return 8;

    puts("CAIRO_SMOKE_OK");
    return 0;
}
