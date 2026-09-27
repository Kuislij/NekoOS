/* A guest-side link and runtime probe for the first packaged graphics library. */
#include <pixman.h>

#include <stdint.h>
#include <stdio.h>

int main(void)
{
    uint32_t pixels[4] = {0};
    pixman_image_t *image = pixman_image_create_bits(
        PIXMAN_a8r8g8b8, 2, 2, pixels, 2 * (int)sizeof pixels[0]);
    if (image == NULL || pixman_version() <= 0) {
        if (image != NULL) pixman_image_unref(image);
        return 1;
    }
    pixman_image_unref(image);
    puts("PIXMAN_RUNTIME_READY");
    return 0;
}
