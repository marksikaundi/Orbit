#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ot.h>
#include <stdint.h>

int orbit_hb_shape(
    const char *font_path,
    int px,
    const uint32_t *cps,
    int cp_count,
    uint32_t *out_glyphs,
    int out_cap
) {
    if (!font_path || !cps || cp_count <= 0 || !out_glyphs || out_cap <= 0) return 0;

    hb_blob_t *blob = hb_blob_create_from_file(font_path);
    if (!blob || hb_blob_get_length(blob) == 0) {
        if (blob) hb_blob_destroy(blob);
        return 0;
    }
    hb_face_t *face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    if (!face) return 0;

    hb_font_t *font = hb_font_create(face);
    hb_ot_font_set_funcs(font);
    const int scale = px > 0 ? px * 64 : 14 * 64;
    hb_font_set_scale(font, scale, scale);

    hb_buffer_t *buf = hb_buffer_create();
    hb_buffer_add_utf32(buf, cps, (int)cp_count, 0, (int)cp_count);
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font, buf, NULL, 0);

    unsigned int n = 0;
    hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buf, &n);
    int out_n = 0;
    for (unsigned int i = 0; i < n && out_n < out_cap; i++) {
        out_glyphs[out_n++] = info[i].codepoint;
    }

    hb_buffer_destroy(buf);
    hb_font_destroy(font);
    hb_face_destroy(face);
    return out_n;
}
