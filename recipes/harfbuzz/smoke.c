#include <hb.h>
#include <hb-ft.h>
#include <hb-glib.h>
#include <hb-gobject.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>

static int shape(hb_font_t *font, const char *text, unsigned expected_max,
                 hb_direction_t expected_direction)
{
    hb_buffer_t *buffer = hb_buffer_create();
    hb_buffer_set_unicode_funcs(buffer, hb_glib_get_unicode_funcs());
    hb_buffer_add_utf8(buffer, text, -1, 0, -1);
    hb_buffer_guess_segment_properties(buffer);
    hb_shape(font, buffer, NULL, 0);
    unsigned count;
    hb_glyph_info_t *glyphs = hb_buffer_get_glyph_infos(buffer, &count);
    hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, NULL);
    int ok = count > 0 && count <= expected_max &&
             hb_buffer_get_direction(buffer) == expected_direction;
    long advance = 0;
    for (unsigned i = 0; i < count; ++i) {
        if (!glyphs[i].codepoint) ok = 0;
        advance += positions[i].x_advance;
    }
    hb_buffer_destroy(buffer);
    return ok && advance > 0;
}

int main(int argc, char **argv)
{
    const char *font_path = argc > 1 ? argv[1] : "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
    FT_Library library;
    FT_Face face;
    if (FT_Init_FreeType(&library) || FT_New_Face(library, font_path, 0, &face) ||
        FT_Set_Char_Size(face, 0, 16 * 64, 96, 96)) return 1;
    hb_font_t *font = hb_ft_font_create_referenced(face);
    /* Default OpenType ligatures collapse six input letters to <= five glyphs. */
    int ok = shape(font, "office", 5, HB_DIRECTION_LTR) &&
             shape(font, "\xd8\xb3\xd9\x84\xd8\xa7\xd9\x85", 4, HB_DIRECTION_RTL) &&
             hb_gobject_buffer_get_type() != 0;
    hb_font_destroy(font);
    FT_Done_Face(face);
    FT_Done_FreeType(library);
    if (!ok) {
        fputs("HarfBuzz failed OpenType ligature/Arabic shaping or GObject registration\n", stderr);
        return 1;
    }
    puts("HARFBUZZ_SMOKE_OK");
    return 0;
}
