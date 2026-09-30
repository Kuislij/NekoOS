#include <fribidi.h>
#include <stdio.h>

int main(void)
{
    const FriBidiChar logical[] = {0x05d0, 0x05d1, 0x05d2};
    FriBidiChar visual[3];
    FriBidiStrIndex logical_to_visual[3];
    FriBidiParType direction = FRIBIDI_PAR_ON;
    if (!fribidi_log2vis(logical, 3, &direction, visual, logical_to_visual, NULL, NULL) ||
        direction != FRIBIDI_PAR_RTL || visual[0] != 0x05d2 || visual[2] != 0x05d0 ||
        logical_to_visual[0] != 2 || logical_to_visual[2] != 0) {
        fputs("FriBidi failed Hebrew RTL reordering\n", stderr);
        return 1;
    }
    puts("FRIBIDI_SMOKE_OK");
    return 0;
}
