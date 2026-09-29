/* Render a glyph from the bitmap font already packaged with NekoOS. */
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>

int main(void)
{
    FT_Library library;
    FT_Face face;
    if (FT_Init_FreeType(&library) != 0)
        return 1;
    if (FT_New_Face(library, "/usr/share/fonts/X11/misc/6x13.pcf", 0, &face) != 0) {
        FT_Done_FreeType(library);
        fputs("FreeType could not open the NekoOS font\n", stderr);
        return 1;
    }
    int ok = FT_Select_Size(face, 0) == 0 &&
             FT_Load_Char(face, 'A', FT_LOAD_RENDER) == 0 &&
             face->glyph->bitmap.width > 0 && face->glyph->bitmap.rows > 0;
    FT_Done_Face(face);
    FT_Done_FreeType(library);
    if (!ok) {
        fputs("FreeType could not render the glyph\n", stderr);
        return 1;
    }
    puts("FREETYPE_RUNTIME_READY");
    return 0;
}
