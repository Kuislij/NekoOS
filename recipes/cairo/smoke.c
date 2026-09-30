#include <cairo.h>
#include <cairo-pdf.h>
#include <cairo-gobject.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int pdf_export(const char *png_path)
{
    size_t length = strlen(png_path);
    if (length > SIZE_MAX - 5)
        return 0;
    char *path = malloc(length + 5);
    if (path == NULL)
        return 0;
    memcpy(path, png_path, length);
    memcpy(path + length, ".pdf", 5);

    cairo_surface_t *surface = cairo_pdf_surface_create(path, 72.0, 72.0);
    cairo_t *cr = NULL;
    FILE *file = NULL;
    int ok = 0;
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS)
        goto cleanup;
    cr = cairo_create(surface);
    cairo_set_source_rgb(cr, 0.0, 0.2, 0.8);
    cairo_rectangle(cr, 8.0, 8.0, 56.0, 56.0);
    cairo_fill(cr);
    cairo_show_page(cr);
    if (cairo_status(cr) != CAIRO_STATUS_SUCCESS)
        goto cleanup;
    cairo_destroy(cr);
    cr = NULL;

    /* Finish forces page streams, object tables and the document trailer out. */
    cairo_surface_finish(surface);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS)
        goto cleanup;
    file = fopen(path, "rb");
    if (file == NULL)
        goto cleanup;
    unsigned char header[8], trailer[6];
    if (fread(header, 1, sizeof header, file) != sizeof header ||
        memcmp(header, "%PDF-", 5) != 0 ||
        header[5] < '1' || header[5] > '9' || header[6] != '.' ||
        header[7] < '0' || header[7] > '9' ||
        fseek(file, 0, SEEK_END) != 0 || ftell(file) <= 128 ||
        fseek(file, -(long)sizeof trailer, SEEK_END) != 0 ||
        fread(trailer, 1, sizeof trailer, file) != sizeof trailer ||
        memcmp(trailer, "%%EOF\n", sizeof trailer) != 0)
        goto cleanup;
    ok = 1;

cleanup:
    if (file != NULL && fclose(file) != 0)
        ok = 0;
    if (cr != NULL)
        cairo_destroy(cr);
    cairo_surface_destroy(surface);
    if (remove(path) != 0)
        ok = 0;
    free(path);
    return ok;
}

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
    if (!pdf_export(argv[1]))
        return 9;

    puts("CAIRO_SMOKE_OK");
    return 0;
}
