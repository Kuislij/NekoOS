/* Match a packaged scalable font through Fontconfig in the guest. */
#include <fontconfig/fontconfig.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    if (!FcInit()) {
        fputs("Fontconfig initialization failed\n", stderr);
        return 1;
    }
    FcPattern *request = FcNameParse((const FcChar8 *) "DejaVu Sans");
    if (request == NULL)
        return 1;
    FcConfigSubstitute(NULL, request, FcMatchPattern);
    FcDefaultSubstitute(request);
    FcResult result;
    FcPattern *match = FcFontMatch(NULL, request, &result);
    FcPatternDestroy(request);
    if (match == NULL)
        return 1;
    FcChar8 *path = NULL;
    int ok = FcPatternGetString(match, FC_FILE, 0, &path) == FcResultMatch &&
             path != NULL &&
             strncmp((const char *) path, "/usr/share/fonts/truetype/dejavu/", 33) == 0;
    FcPatternDestroy(match);
    FcFini();
    if (!ok) {
        fputs("Fontconfig did not find a packaged DejaVu font\n", stderr);
        return 1;
    }
    puts("FONTCONFIG_RUNTIME_READY");
    return 0;
}
