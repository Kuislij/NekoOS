/* Round-trip pixels through the packaged libpng and zlib ABIs. */
#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
    static const unsigned char pixels[] = {
        255, 0, 0, 255, 0, 255, 0, 128,
        0, 0, 255, 64, 255, 255, 255, 0
    };
    png_image writer = {0};
    png_image reader = {0};
    unsigned char decoded[sizeof pixels];
    png_alloc_size_t size = 0;
    unsigned char *encoded = NULL;
    int status = 1;

    writer.version = PNG_IMAGE_VERSION;
    writer.width = 2;
    writer.height = 2;
    writer.format = PNG_FORMAT_RGBA;
    if (!png_image_write_to_memory(&writer, NULL, &size, 0, pixels, 0, NULL))
        goto done;
    encoded = malloc(size);
    if (encoded == NULL ||
        !png_image_write_to_memory(&writer, encoded, &size, 0, pixels, 0, NULL))
        goto done;

    reader.version = PNG_IMAGE_VERSION;
    if (!png_image_begin_read_from_memory(&reader, encoded, size))
        goto done;
    if (reader.width != 2 || reader.height != 2)
        goto done;
    reader.format = PNG_FORMAT_RGBA;
    if (!png_image_finish_read(&reader, NULL, decoded, 0, NULL) ||
        memcmp(decoded, pixels, sizeof pixels) != 0)
        goto done;
    puts("LIBPNG_RUNTIME_READY");
    status = 0;

done:
    png_image_free(&reader);
    png_image_free(&writer);
    free(encoded);
    return status;
}
