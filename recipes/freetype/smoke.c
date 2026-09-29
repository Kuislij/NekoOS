/* Exercise the packaged FreeType ABI and rasterizer with a real font. */
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>

int main(int argc, char **argv)
{
    FT_Library library;
    FT_Face face;
    FT_Int major, minor, patch;
    int result = 1;

    if (argc != 2 || FT_Init_FreeType(&library) != 0)
        return 1;

    FT_Library_Version(library, &major, &minor, &patch);
    if (major != 2 || minor != 14 || patch != 3)
        goto done;
    if (FT_New_Face(library, argv[1], 0, &face) != 0)
        goto done;
    FT_Error size_error = FT_IS_SCALABLE(face)
        ? FT_Set_Pixel_Sizes(face, 0, 16)
        : FT_Select_Size(face, 0);
    if (size_error == 0 &&
        FT_Load_Char(face, 'A', FT_LOAD_RENDER) == 0 &&
        face->glyph->bitmap.width > 0 && face->glyph->bitmap.rows > 0) {
        puts("FREETYPE_RUNTIME_READY");
        result = 0;
    }
    FT_Done_Face(face);

done:
    FT_Done_FreeType(library);
    return result;
}
