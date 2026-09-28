/* NekoOS framebuffer desktop prototype. No windowing libraries are required. */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/kd.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "neko-files.h"
#include "neko-system.h"
#include "neko-windows.h"

#define MAX_INPUTS 32
#define MAX_DIMENSION 4096
#define MAX_FB_BYTES (128u * 1024u * 1024u)

typedef struct {
    int width;
    int height;
    uint32_t *pixels; /* 0x00RRGGBB */
} Canvas;

typedef struct {
    int fd;
    void *mapping;
    size_t length;
    struct fb_fix_screeninfo fix;
    struct fb_var_screeninfo var;
} Framebuffer;

typedef struct {
    struct {
        int fd;
        struct input_absinfo abs_x;
        struct input_absinfo abs_y;
        int absolute;
    } device[MAX_INPUTS];
    size_t count;
} Inputs;

enum App { APP_FILES, APP_SYSTEM, APP_ABOUT, APP_HELP, APP_COUNT };
enum EditMode { EDIT_NONE, EDIT_CREATE, EDIT_MKDIR, EDIT_RENAME };

typedef struct {
    NekoWindowManager wm;
    NekoFiles files;
    NekoSystemInfo system;
    int files_ready;
    int app_ids[APP_COUNT];
    size_t selected_file;
    size_t file_scroll;
    int has_selection;
    enum EditMode edit_mode;
    char edit_name[64];
    char message[128];
    char preview[NEKO_FILES_MAX_PREVIEW + 1];
    int preview_truncated;
    int show_preview;
    int mouse_x;
    int mouse_y;
    int mouse_present;
    int mouse_down;
    int drag_id;
    int drag_offset_x;
    int drag_offset_y;
    int shift_down;
} Desktop;

static volatile sig_atomic_t stop_requested;

static const uint32_t C_BG = 0x0b1426;
static const uint32_t C_BAR = 0x121f35;
static const uint32_t C_PANEL = 0x172640;
static const uint32_t C_PANEL_LIGHT = 0x1d3150;
static const uint32_t C_ACCENT = 0x65dfd2;
static const uint32_t C_PINK = 0xf79ab7;
static const uint32_t C_TEXT = 0xf1f6ff;
static const uint32_t C_MUTED = 0xa9bbd2;

static void on_signal(int sig)
{
    (void)sig;
    stop_requested = 1;
}

static void fill_rect(Canvas *c, int x, int y, int width, int height, uint32_t color)
{
    int x0 = x < 0 ? 0 : x;
    int y0 = y < 0 ? 0 : y;
    int x1 = x + width > c->width ? c->width : x + width;
    int y1 = y + height > c->height ? c->height : y + height;
    if (x1 <= x0 || y1 <= y0) return;
    for (int row = y0; row < y1; row++) {
        uint32_t *line = c->pixels + (size_t)row * c->width + x0;
        for (int col = x0; col < x1; col++) *line++ = color;
    }
}

static void round_rect(Canvas *c, int x, int y, int width, int height,
                       int radius, uint32_t color)
{
    if (width <= 0 || height <= 0) return;
    if (radius > width / 2) radius = width / 2;
    if (radius > height / 2) radius = height / 2;
    fill_rect(c, x + radius, y, width - 2 * radius, height, color);
    fill_rect(c, x, y + radius, width, height - 2 * radius, color);
    for (int dy = 0; dy < radius; dy++) {
        for (int dx = 0; dx < radius; dx++) {
            int a = radius - dx - 1;
            int b = radius - dy - 1;
            if (a * a + b * b > radius * radius) continue;
            fill_rect(c, x + dx, y + dy, 1, 1, color);
            fill_rect(c, x + width - dx - 1, y + dy, 1, 1, color);
            fill_rect(c, x + dx, y + height - dy - 1, 1, 1, color);
            fill_rect(c, x + width - dx - 1, y + height - dy - 1, 1, 1, color);
        }
    }
}

static void disc(Canvas *c, int cx, int cy, int r, uint32_t color)
{
    for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
            if (dx * dx + dy * dy <= r * r)
                fill_rect(c, cx + dx, cy + dy, 1, 1, color);
        }
    }
}

/* Small original 5x7 font; rows use the low five bits, left to right. */
struct Glyph { char ch; uint8_t row[7]; };
static const struct Glyph glyphs[] = {
    {'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
    {'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
    {'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
    {'G',{14,17,16,23,17,17,15}}, {'H',{17,17,17,31,17,17,17}},
    {'I',{31,4,4,4,4,4,31}}, {'J',{7,2,2,2,18,18,12}},
    {'K',{17,18,20,24,20,18,17}}, {'L',{16,16,16,16,16,16,31}},
    {'M',{17,27,21,21,17,17,17}}, {'N',{17,25,21,19,17,17,17}},
    {'O',{14,17,17,17,17,17,14}}, {'P',{30,17,17,30,16,16,16}},
    {'Q',{14,17,17,17,21,18,13}}, {'R',{30,17,17,30,20,18,17}},
    {'S',{15,16,16,14,1,1,30}}, {'T',{31,4,4,4,4,4,4}},
    {'U',{17,17,17,17,17,17,14}}, {'V',{17,17,17,17,17,10,4}},
    {'W',{17,17,17,21,21,21,10}}, {'X',{17,17,10,4,10,17,17}},
    {'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}},
    {'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}},
    {'2',{14,17,1,2,4,8,31}}, {'3',{30,1,1,14,1,1,30}},
    {'4',{2,6,10,18,31,2,2}}, {'5',{31,16,16,30,1,1,30}},
    {'6',{14,16,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}},
    {'8',{14,17,17,14,17,17,14}}, {'9',{14,17,17,15,1,1,14}},
    {' ',{0,0,0,0,0,0,0}}, {'-',{0,0,0,31,0,0,0}},
    {'.',{0,0,0,0,0,12,12}}, {':',{0,12,12,0,12,12,0}},
    {'_',{0,0,0,0,0,0,31}}, {',',{0,0,0,0,12,12,8}},
    {'/',{1,1,2,4,8,16,16}}, {'>',{16,8,4,2,4,8,16}},
    {'?',{14,17,1,2,4,0,4}},
};

static const uint8_t *glyph_for(char ch)
{
    if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
    for (size_t i = 0; i < sizeof glyphs / sizeof glyphs[0]; i++)
        if (glyphs[i].ch == ch) return glyphs[i].row;
    return glyphs[sizeof glyphs / sizeof glyphs[0] - 1].row;
}

static void draw_text(Canvas *c, int x, int y, int size, uint32_t color,
                      const char *message)
{
    for (const char *p = message; *p; p++, x += 6 * size) {
        const uint8_t *g = glyph_for(*p);
        for (int row = 0; row < 7; row++)
            for (int col = 0; col < 5; col++)
                if (g[row] & (1u << (4 - col)))
                    fill_rect(c, x + col * size, y + row * size,
                              size, size, color);
    }
}

static void draw_cat(Canvas *c, int x, int y, int size)
{
    int ear = size / 4;
    int head_y = y + ear;
    for (int i = 0; i < ear; i++) {
        fill_rect(c, x + i, y + i, ear - i, 1, C_ACCENT);
        fill_rect(c, x + size - ear, y + i, ear - i, 1, C_ACCENT);
    }
    round_rect(c, x, head_y, size, size - ear, size / 4, C_ACCENT);
    disc(c, x + size / 3, head_y + size / 2, size / 15 + 1, C_BG);
    disc(c, x + size * 2 / 3, head_y + size / 2, size / 15 + 1, C_BG);
    fill_rect(c, x + size / 2 - size / 16, head_y + size * 2 / 3,
              size / 8 + 1, size / 14 + 1, C_PINK);
}

static void draw_text_n(Canvas *c, int x, int y, int size, uint32_t color,
                        const char *message, size_t limit)
{
    for (size_t i = 0; message[i] && i < limit; i++, x += 6 * size) {
        unsigned char ch = (unsigned char)message[i];
        const uint8_t *g = glyph_for(ch >= 32 && ch < 127 ? (char)ch : '?');
        for (int row = 0; row < 7; row++)
            for (int col = 0; col < 5; col++)
                if (g[row] & (1u << (4 - col)))
                    fill_rect(c, x + col * size, y + row * size,
                              size, size, color);
    }
}

static void draw_button(Canvas *c, int x, int y, int width, int height,
                        const char *label, int active)
{
    round_rect(c, x, y, width, height, 6, active ? C_ACCENT : C_PANEL_LIGHT);
    draw_text_n(c, x + 9, y + (height - 7) / 2, 1,
                active ? C_BG : C_TEXT, label, (size_t)(width - 12) / 6);
}

static const char *app_title(enum App app)
{
    static const char *titles[APP_COUNT] = { "FILES", "SYSTEM", "ABOUT", "HELP" };
    return titles[app];
}

static enum App app_for_window(const Desktop *d, int id)
{
    for (int app = 0; app < APP_COUNT; app++)
        if (d->app_ids[app] == id) return (enum App)app;
    return APP_COUNT;
}

static int files_rows(const NekoWindow *w)
{
    int rows = (w->height - 160) / 28;
    if (rows < 1) rows = 1;
    if (rows > 12) rows = 12;
    return rows;
}

static void keep_selection_visible(Desktop *d, const NekoWindow *w)
{
    int rows = files_rows(w);
    if (!d->has_selection || d->files.entry_count == 0) {
        d->file_scroll = 0;
        return;
    }
    if (d->selected_file < d->file_scroll) d->file_scroll = d->selected_file;
    if (d->selected_file >= d->file_scroll + (size_t)rows)
        d->file_scroll = d->selected_file - (size_t)rows + 1;
}

static void file_status(Desktop *d, const char *operation, int result)
{
    if (result == 0)
        snprintf(d->message, sizeof d->message, "%s OK", operation);
    else
        snprintf(d->message, sizeof d->message, "%s: %s",
                 operation, strerror(-result));
}

static void refresh_preview(Desktop *d)
{
    d->preview[0] = '\0';
    d->preview_truncated = 0;
    if (!d->files_ready || !d->has_selection ||
        d->selected_file >= d->files.entry_count ||
        d->files.entries[d->selected_file].kind != NEKO_FILES_REGULAR) return;
    int result = neko_files_preview(&d->files, d->selected_file,
                                    d->preview, sizeof d->preview,
                                    &d->preview_truncated);
    if (result < 0)
        snprintf(d->preview, sizeof d->preview, "PREVIEW: %s",
                 strerror(-result));
}

static void draw_file_preview(Canvas *c, const Desktop *d,
                              int x, int y, int width, int height)
{
    fill_rect(c, x, y, width, height, C_BAR);
    if (!d->has_selection || d->selected_file >= d->files.entry_count) {
        draw_text_n(c, x + 12, y + 14, 1, C_MUTED, "SELECT A FILE", (size_t)(width - 20) / 6);
        return;
    }
    const NekoFileEntry *entry = &d->files.entries[d->selected_file];
    draw_text_n(c, x + 12, y + 14, 1, C_ACCENT, entry->display_name,
                (size_t)(width - 20) / 6);
    fill_rect(c, x + 12, y + 34, width - 24, 1, C_PANEL_LIGHT);
    if (entry->kind == NEKO_FILES_DIRECTORY) {
        draw_text_n(c, x + 12, y + 50, 1, C_MUTED, "DIRECTORY - ENTER TO OPEN",
                    (size_t)(width - 20) / 6);
        return;
    }
    if (entry->kind != NEKO_FILES_REGULAR) {
        draw_text_n(c, x + 12, y + 50, 1, C_MUTED, "NO TEXT PREVIEW",
                    (size_t)(width - 20) / 6);
        return;
    }
    const char *p = d->preview;
    int line_y = y + 50;
    size_t columns = (size_t)(width - 24) / 6;
    if (columns == 0) return;
    while (*p && line_y + 8 < y + height) {
        char line[96];
        size_t used = 0;
        while (*p && *p != '\n' && used < sizeof line - 1 && used < columns)
            line[used++] = *p++;
        line[used] = '\0';
        draw_text(c, x + 12, line_y, 1, C_TEXT, line);
        line_y += 13;
        if (*p == '\n') p++;
    }
    if (d->preview_truncated && line_y + 8 < y + height)
        draw_text(c, x + 12, line_y, 1, C_MUTED, "...");
}

static void draw_files(Canvas *c, const Desktop *d, const NekoWindow *w)
{
    int x = w->x, y = w->y, width = w->width, height = w->height;
    draw_button(c, x + 14, y + 38, 43, 26, "UP", 0);
    draw_button(c, x + 63, y + 38, 66, 26, "NEW FILE", 0);
    draw_button(c, x + 135, y + 38, 72, 26, "NEW DIR", 0);
    draw_button(c, x + 213, y + 38, 80, 26, "RENAME", 0);
    if (!d->files_ready) {
        draw_text(c, x + 18, y + 87, 1, C_PINK, "HOME FOLDER UNAVAILABLE");
        return;
    }
    draw_text_n(c, x + 17, y + 79, 1, C_MUTED,
                d->files.relative_path, (size_t)(width - 34) / 6);
    int split = width >= 540 && !d->show_preview;
    int list_width = split ? 250 : width - 28;
    if (d->show_preview) {
        draw_file_preview(c, d, x + 14, y + 110, width - 28, height - 157);
        draw_text(c, x + 18, y + height - 42, 1, C_MUTED,
                  "ESC TO RETURN TO LIST");
    } else {
        int rows = files_rows(w);
        for (int row = 0; row < rows; row++) {
            size_t index = d->file_scroll + (size_t)row;
            if (index >= d->files.entry_count) break;
            const NekoFileEntry *entry = &d->files.entries[index];
            int row_y = y + 112 + row * 28;
            if (d->has_selection && index == d->selected_file)
                round_rect(c, x + 13, row_y, list_width, 25, 5, C_PANEL_LIGHT);
            const char *prefix = entry->kind == NEKO_FILES_DIRECTORY ? "D" :
                                 entry->kind == NEKO_FILES_REGULAR ? "F" : "?";
            draw_text(c, x + 19, row_y + 9, 1, C_ACCENT, prefix);
            draw_text_n(c, x + 36, row_y + 9, 1, C_TEXT, entry->display_name,
                        (size_t)(list_width - 45) / 6);
        }
        if (d->files.truncated)
            draw_text(c, x + 17, y + height - 64, 1, C_MUTED,
                      "MORE ITEMS NOT SHOWN");
        if (split)
            draw_file_preview(c, d, x + 279, y + 110, width - 293,
                              height - 157);
    }
    if (d->edit_mode != EDIT_NONE) {
        fill_rect(c, x + 13, y + height - 67, width - 26, 28, C_BAR);
        draw_text_n(c, x + 20, y + height - 58, 1, C_ACCENT,
                    d->edit_mode == EDIT_CREATE ? "NEW FILE:" :
                    d->edit_mode == EDIT_MKDIR ? "NEW DIR:" : "RENAME:", 9);
        draw_text_n(c, x + 80, y + height - 58, 1, C_TEXT, d->edit_name,
                    (size_t)(width - 108) / 6);
        draw_text(c, x + width - 22, y + height - 58, 1, C_PINK, "_");
    }
    draw_text_n(c, x + 17, y + height - 25, 1,
                d->message[0] ? C_ACCENT : C_MUTED,
                d->message[0] ? d->message : "ENTER OPEN  ARROWS SELECT",
                (size_t)(width - 34) / 6);
}

static void draw_system(Canvas *c, const Desktop *d, const NekoWindow *w)
{
    int x = w->x + 20, y = w->y + 49;
    char value[160];
    draw_text(c, x, y, 2, C_ACCENT, "SYSTEM STATUS");
    y += 42;
    if (d->system.valid & NEKO_SYSTEM_KERNEL_RELEASE)
        snprintf(value, sizeof value, "KERNEL  %.75s", d->system.kernel_release);
    else strcpy(value, "KERNEL  UNAVAILABLE");
    draw_text_n(c, x, y, 1, C_TEXT, value, (size_t)(w->width - 40) / 6);
    y += 30;
    if (d->system.valid & NEKO_SYSTEM_CPU_COUNT)
        snprintf(value, sizeof value, "CPUS    %u", d->system.cpu_count);
    else strcpy(value, "CPUS    UNAVAILABLE");
    draw_text(c, x, y, 1, C_TEXT, value);
    y += 30;
    if (d->system.valid & NEKO_SYSTEM_UPTIME)
        snprintf(value, sizeof value, "UPTIME  %llu MIN",
                 (unsigned long long)(d->system.uptime_seconds / 60u));
    else strcpy(value, "UPTIME  UNAVAILABLE");
    draw_text(c, x, y, 1, C_TEXT, value);
    y += 30;
    if ((d->system.valid & (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE)) ==
        (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE))
        snprintf(value, sizeof value, "MEMORY  %llu / %llu MIB FREE",
                 (unsigned long long)(d->system.memory_available_bytes / 1048576u),
                 (unsigned long long)(d->system.memory_total_bytes / 1048576u));
    else strcpy(value, "MEMORY  UNAVAILABLE");
    draw_text_n(c, x, y, 1, C_TEXT, value, (size_t)(w->width - 40) / 6);
    y += 30;
    if ((d->system.valid & (NEKO_SYSTEM_DISK_TOTAL | NEKO_SYSTEM_DISK_FREE)) ==
        (NEKO_SYSTEM_DISK_TOTAL | NEKO_SYSTEM_DISK_FREE))
        snprintf(value, sizeof value, "DISK    %llu / %llu MIB FREE",
                 (unsigned long long)(d->system.disk_available_bytes / 1048576u),
                 (unsigned long long)(d->system.disk_total_bytes / 1048576u));
    else strcpy(value, "DISK    UNAVAILABLE");
    draw_text_n(c, x, y, 1, C_TEXT, value, (size_t)(w->width - 40) / 6);
    draw_text(c, x, w->y + w->height - 34, 1, C_MUTED,
              "LIVE DATA FROM THE RUNNING SYSTEM");
}

static void draw_about(Canvas *c, const NekoWindow *w)
{
    int x = w->x + 25, y = w->y + 47;
    draw_cat(c, x, y + 4, 75);
    draw_text(c, x + 94, y + 8, 2, C_ACCENT, "NEKOOS");
    draw_text(c, x + 94, y + 39, 1, C_MUTED, "LINUX BASED OPERATING SYSTEM");
    fill_rect(c, x, y + 107, w->width - 50, 1, C_PANEL_LIGHT);
    draw_text(c, x, y + 132, 1, C_TEXT, "GRAPHICAL DESKTOP SHELL");
    draw_text(c, x, y + 155, 1, C_TEXT, "FILES AND SYSTEM TOOLS");
    draw_text(c, x, y + 178, 1, C_MUTED, "EARLY DEVELOPMENT BUILD");
}

static void draw_help(Canvas *c, const NekoWindow *w)
{
    int x = w->x + 23, y = w->y + 49;
    draw_text(c, x, y, 2, C_ACCENT, "DESKTOP HELP");
    y += 43;
    draw_text(c, x, y, 1, C_TEXT, "CLICK AN ICON TO OPEN A WINDOW");
    draw_text(c, x, y + 23, 1, C_TEXT, "DRAG TITLE BAR TO MOVE");
    draw_text(c, x, y + 46, 1, C_TEXT, "TAB SWITCHES WINDOWS");
    draw_text(c, x, y + 69, 1, C_TEXT, "ESC CLOSES WINDOW");
    draw_text(c, x, y + 92, 1, C_TEXT, "FILES: ARROWS AND ENTER");
    draw_text(c, x, y + 115, 1, C_TEXT, "N NEW FILE  M NEW FOLDER");
    draw_text(c, x, y + 138, 1, C_TEXT, "R RENAME SELECTED FILE");
    draw_text(c, x, y + 161, 1, C_MUTED, "ESC WITH NO WINDOWS EXITS");
}

static void draw_window(Canvas *c, const Desktop *d, const NekoWindow *w)
{
    enum App app = app_for_window(d, w->id);
    if (app == APP_COUNT || w->minimized) return;
    int focused = d->wm.focused_id == w->id;
    round_rect(c, w->x + 5, w->y + 7, w->width, w->height, 8, C_BG);
    round_rect(c, w->x - 2, w->y - 2, w->width + 4, w->height + 4, 9,
               focused ? C_ACCENT : C_PANEL_LIGHT);
    round_rect(c, w->x, w->y, w->width, w->height, 8, C_PANEL);
    fill_rect(c, w->x, w->y + 27, w->width, 2, C_PANEL_LIGHT);
    draw_text(c, w->x + 14, w->y + 10, 1, C_TEXT, app_title(app));
    draw_button(c, w->x + w->width - 53, w->y + 3, 24, 22, "_", 0);
    draw_button(c, w->x + w->width - 26, w->y + 3, 23, 22, "X", 0);
    switch (app) {
    case APP_FILES: draw_files(c, d, w); break;
    case APP_SYSTEM: draw_system(c, d, w); break;
    case APP_ABOUT: draw_about(c, w); break;
    case APP_HELP: draw_help(c, w); break;
    default: break;
    }
}

static void draw_desktop(Canvas *c, const Desktop *d)
{
    for (int y = 0; y < c->height; y++) {
        uint32_t shade = (uint32_t)(10 + (y * 22) / c->height);
        fill_rect(c, 0, y, c->width, 1, (shade << 16) | ((shade + 11) << 8) | (shade + 26));
    }
    fill_rect(c, 0, 0, c->width, 43, C_BAR);
    draw_cat(c, 10, 6, 31);
    draw_text(c, 54, 16, 2, C_TEXT, "NEKOOS");
    if (c->width >= 700)
        draw_text(c, c->width - 178, 19, 1, C_MUTED, "DESKTOP SHELL");
    for (int app = 0; app < APP_COUNT; app++) {
        int x = 24 + app * 100;
        int y = 68;
        round_rect(c, x, y, 84, 71, 11, C_PANEL);
        round_rect(c, x + 24, y + 12, 36, 36, 8,
                   app == APP_FILES ? C_ACCENT :
                   app == APP_SYSTEM ? C_PINK : C_PANEL_LIGHT);
        draw_text(c, x + 33, y + 25, 2,
                  app == APP_FILES || app == APP_SYSTEM ? C_BG : C_TEXT,
                  app == APP_FILES ? "F" : app == APP_SYSTEM ? "S" :
                  app == APP_ABOUT ? "A" : "H");
        draw_text_n(c, x + 9, y + 55, 1, C_TEXT, app_title((enum App)app), 11);
    }
    fill_rect(c, 0, c->height - 45, c->width, 45, C_BAR);
    draw_button(c, 11, c->height - 38, 64, 31, "NEKO", 1);
    int task_width = (c->width - 95) / APP_COUNT;
    if (task_width > 140) task_width = 140;
    for (int app = 0; app < APP_COUNT; app++) {
        int id = d->app_ids[app];
        if (!id) continue;
        draw_button(c, 85 + app * task_width, c->height - 38,
                    task_width - 5, 31, app_title((enum App)app),
                    d->wm.focused_id == id);
    }
    for (size_t i = 0; i < d->wm.count; i++)
        draw_window(c, d, neko_wm_at_z(&d->wm, i));
}

static void draw_cursor(Canvas *c, int x, int y)
{
    fill_rect(c, x - 1, y - 1, 3, 19, C_BG);
    fill_rect(c, x - 1, y - 1, 17, 3, C_BG);
    fill_rect(c, x, y, 1, 17, C_TEXT);
    fill_rect(c, x, y, 15, 1, C_TEXT);
    for (int i = 0; i < 10; i++) fill_rect(c, x + i, y + i, 2, 2, C_TEXT);
}

static void render(Canvas *c, const Desktop *d)
{
    draw_desktop(c, d);
    if (d->mouse_present) draw_cursor(c, d->mouse_x, d->mouse_y);
}


static uint32_t channel(unsigned value, struct fb_bitfield field)
{
    if (!field.length) return 0;
    unsigned limit = (1u << field.length) - 1u;
    unsigned scaled = (value * limit + 127u) / 255u;
    return scaled << field.offset;
}

static int open_framebuffer(Framebuffer *fb)
{
    memset(fb, 0, sizeof *fb);
    fb->fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
    if (fb->fd < 0) { perror("/dev/fb0"); return -1; }
    if (ioctl(fb->fd, FBIOGET_FSCREENINFO, &fb->fix) < 0 ||
        ioctl(fb->fd, FBIOGET_VSCREENINFO, &fb->var) < 0) {
        perror("framebuffer information");
        close(fb->fd);
        return -1;
    }
    unsigned bpp = fb->var.bits_per_pixel;
    unsigned bytes = bpp / 8;
    if (fb->var.xres < 400 || fb->var.yres < 320 ||
        fb->var.xres > MAX_DIMENSION || fb->var.yres > MAX_DIMENSION ||
        (bpp != 16 && bpp != 24 && bpp != 32) ||
        fb->var.red.length > 16 || fb->var.green.length > 16 ||
        fb->var.blue.length > 16 ||
        fb->var.red.offset + fb->var.red.length > bpp ||
        fb->var.green.offset + fb->var.green.length > bpp ||
        fb->var.blue.offset + fb->var.blue.length > bpp ||
        ((uint64_t)fb->var.xoffset + fb->var.xres) * bytes > fb->fix.line_length ||
        fb->fix.smem_len == 0 || fb->fix.smem_len > MAX_FB_BYTES ||
        ((uint64_t)fb->var.yoffset + fb->var.yres) * fb->fix.line_length >
            fb->fix.smem_len) {
        fprintf(stderr, "Unsupported framebuffer mode or geometry\n");
        close(fb->fd);
        return -1;
    }
    fb->length = fb->fix.smem_len;
    fb->mapping = mmap(NULL, fb->length, PROT_READ | PROT_WRITE,
                       MAP_SHARED, fb->fd, 0);
    if (fb->mapping == MAP_FAILED) {
        perror("map framebuffer");
        close(fb->fd);
        return -1;
    }
    return 0;
}

static void flush_framebuffer(const Canvas *c, const Framebuffer *fb)
{
    const unsigned bytes = fb->var.bits_per_pixel / 8;
    for (int y = 0; y < c->height; y++) {
        uint8_t *dst = (uint8_t *)fb->mapping +
            (size_t)(y + fb->var.yoffset) * fb->fix.line_length +
            (size_t)fb->var.xoffset * bytes;
        const uint32_t *src = c->pixels + (size_t)y * c->width;
        for (int x = 0; x < c->width; x++) {
            uint32_t rgb = src[x];
            uint32_t value = channel((rgb >> 16) & 255u, fb->var.red) |
                channel((rgb >> 8) & 255u, fb->var.green) |
                channel(rgb & 255u, fb->var.blue);
            if (fb->var.transp.length && fb->var.transp.length <= 16 &&
                fb->var.transp.offset + fb->var.transp.length <=
                    fb->var.bits_per_pixel)
                value |= ((1u << fb->var.transp.length) - 1u) <<
                    fb->var.transp.offset;
            memcpy(dst + (size_t)x * bytes, &value, bytes);
        }
    }
}

static void open_inputs(Inputs *inputs)
{
    memset(inputs, 0, sizeof *inputs);
    for (int i = 0; i < MAX_INPUTS; i++) {
        char path[64];
        snprintf(path, sizeof path, "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue;
        size_t index = inputs->count++;
        inputs->device[index].fd = fd;
        if (ioctl(fd, EVIOCGABS(ABS_X), &inputs->device[index].abs_x) == 0 &&
            ioctl(fd, EVIOCGABS(ABS_Y), &inputs->device[index].abs_y) == 0 &&
            inputs->device[index].abs_x.maximum >
                inputs->device[index].abs_x.minimum &&
            inputs->device[index].abs_y.maximum >
                inputs->device[index].abs_y.minimum)
            inputs->device[index].absolute = 1;
    }
}

static void close_inputs(Inputs *inputs)
{
    for (size_t i = 0; i < inputs->count; i++) close(inputs->device[i].fd);
}

static void desktop_init(Desktop *d, int width, int height)
{
    memset(d, 0, sizeof *d);
    neko_wm_init(&d->wm, width, height);
    d->mouse_x = width / 2;
    d->mouse_y = height / 2;
    int result = neko_files_init(&d->files, "/home/neko");
    d->files_ready = result == 0;
    if (result < 0) file_status(d, "HOME", result);
    (void)neko_system_read(&d->system);
}

static void desktop_close(Desktop *d)
{
    if (d->files_ready) neko_files_close(&d->files);
}

static void open_app(Desktop *d, enum App app)
{
    int id = d->app_ids[app];
    if (id) {
        (void)neko_wm_restore(&d->wm, id);
        if (app == APP_SYSTEM) (void)neko_system_read(&d->system);
        if (app == APP_FILES && d->files_ready)
            (void)neko_files_refresh(&d->files);
        return;
    }
    int screen_w = d->wm.screen_width, screen_h = d->wm.screen_height;
    int width = app == APP_FILES ? screen_w * 54 / 100 :
                app == APP_SYSTEM ? screen_w * 37 / 100 : screen_w / 2;
    int height = app == APP_FILES ? screen_h * 65 / 100 :
                 app == APP_SYSTEM ? screen_h * 51 / 100 : screen_h / 2;
    if (width < 335) width = 335;
    if (height < 265) height = 265;
    if (width > 680) width = 680;
    if (height > 510) height = 510;
    int x = app == APP_FILES ? 45 :
            app == APP_SYSTEM ? screen_w - width - 25 : 170 + (int)app * 35;
    int y = app == APP_FILES ? 145 :
            app == APP_SYSTEM ? 175 : 120 + (int)app * 25;
    if (y + height > screen_h - 50) y = screen_h - 50 - height;
    if (y < 44) y = 44;
    id = neko_wm_create(&d->wm, app_title(app), x, y, width, height);
    d->app_ids[app] = id;
    if (app == APP_SYSTEM) (void)neko_system_read(&d->system);
    if (app == APP_FILES && d->files_ready) {
        int result = neko_files_refresh(&d->files);
        if (result < 0) file_status(d, "REFRESH", result);
    }
}

static void close_app(Desktop *d, int id)
{
    enum App app = app_for_window(d, id);
    if (app == APP_COUNT) return;
    (void)neko_wm_close(&d->wm, id);
    d->app_ids[app] = 0;
    if (app == APP_FILES) {
        d->edit_mode = EDIT_NONE;
        d->show_preview = 0;
    }
}

static void select_file(Desktop *d, size_t index)
{
    if (!d->files_ready || index >= d->files.entry_count) return;
    d->has_selection = 1;
    d->selected_file = index;
    d->show_preview = 0;
    refresh_preview(d);
    const NekoWindow *w = neko_wm_get(&d->wm, d->app_ids[APP_FILES]);
    if (w) keep_selection_visible(d, w);
}

static void reset_file_selection(Desktop *d)
{
    d->has_selection = 0;
    d->file_scroll = 0;
    d->show_preview = 0;
    d->preview[0] = '\0';
}

static void file_up(Desktop *d)
{
    if (!d->files_ready) return;
    int result = neko_files_up(&d->files);
    file_status(d, "UP", result);
    if (result == 0) reset_file_selection(d);
}

static void open_selected_file(Desktop *d)
{
    if (!d->files_ready || !d->has_selection ||
        d->selected_file >= d->files.entry_count) return;
    const NekoFileEntry *entry = &d->files.entries[d->selected_file];
    if (entry->kind == NEKO_FILES_DIRECTORY) {
        int result = neko_files_enter(&d->files, d->selected_file);
        file_status(d, "OPEN", result);
        if (result == 0) reset_file_selection(d);
    } else if (entry->kind == NEKO_FILES_REGULAR) {
        refresh_preview(d);
        d->show_preview = 1;
    } else {
        snprintf(d->message, sizeof d->message, "CANNOT OPEN THIS ITEM");
    }
}

static void start_edit(Desktop *d, enum EditMode mode)
{
    if (!d->files_ready) return;
    if (mode == EDIT_RENAME &&
        (!d->has_selection || d->selected_file >= d->files.entry_count ||
         d->files.entries[d->selected_file].kind != NEKO_FILES_REGULAR)) {
        snprintf(d->message, sizeof d->message, "SELECT A REGULAR FILE");
        return;
    }
    if (mode == EDIT_RENAME &&
        strlen(d->files.entries[d->selected_file].name) >= sizeof d->edit_name) {
        snprintf(d->message, sizeof d->message, "NAME TOO LONG TO EDIT");
        return;
    }
    d->edit_mode = mode;
    d->edit_name[0] = '\0';
    d->show_preview = 0;
    if (mode == EDIT_RENAME)
        snprintf(d->edit_name, sizeof d->edit_name, "%s",
                 d->files.entries[d->selected_file].name);
    snprintf(d->message, sizeof d->message, "TYPE NAME THEN ENTER");
}

static void submit_edit(Desktop *d)
{
    if (!d->edit_name[0]) {
        snprintf(d->message, sizeof d->message, "NAME CANNOT BE EMPTY");
        return;
    }
    int result = d->edit_mode == EDIT_CREATE
        ? neko_files_create_file(&d->files, d->edit_name)
        : d->edit_mode == EDIT_MKDIR
          ? neko_files_create_dir(&d->files, d->edit_name)
          : neko_files_rename(&d->files, d->selected_file, d->edit_name);
    file_status(d, d->edit_mode == EDIT_CREATE ? "CREATE FILE" :
                   d->edit_mode == EDIT_MKDIR ? "CREATE DIR" : "RENAME", result);
    if (result == 0) {
        d->edit_mode = EDIT_NONE;
        reset_file_selection(d);
    }
}

static char key_character(unsigned code, int shift)
{
    switch (code) {
    case KEY_A: return shift ? 'A' : 'a';
    case KEY_B: return shift ? 'B' : 'b';
    case KEY_C: return shift ? 'C' : 'c';
    case KEY_D: return shift ? 'D' : 'd';
    case KEY_E: return shift ? 'E' : 'e';
    case KEY_F: return shift ? 'F' : 'f';
    case KEY_G: return shift ? 'G' : 'g';
    case KEY_H: return shift ? 'H' : 'h';
    case KEY_I: return shift ? 'I' : 'i';
    case KEY_J: return shift ? 'J' : 'j';
    case KEY_K: return shift ? 'K' : 'k';
    case KEY_L: return shift ? 'L' : 'l';
    case KEY_M: return shift ? 'M' : 'm';
    case KEY_N: return shift ? 'N' : 'n';
    case KEY_O: return shift ? 'O' : 'o';
    case KEY_P: return shift ? 'P' : 'p';
    case KEY_Q: return shift ? 'Q' : 'q';
    case KEY_R: return shift ? 'R' : 'r';
    case KEY_S: return shift ? 'S' : 's';
    case KEY_T: return shift ? 'T' : 't';
    case KEY_U: return shift ? 'U' : 'u';
    case KEY_V: return shift ? 'V' : 'v';
    case KEY_W: return shift ? 'W' : 'w';
    case KEY_X: return shift ? 'X' : 'x';
    case KEY_Y: return shift ? 'Y' : 'y';
    case KEY_Z: return shift ? 'Z' : 'z';
    case KEY_0: return '0';
    case KEY_1: return '1';
    case KEY_2: return '2';
    case KEY_3: return '3';
    case KEY_4: return '4';
    case KEY_5: return '5';
    case KEY_6: return '6';
    case KEY_7: return '7';
    case KEY_8: return '8';
    case KEY_9: return '9';
    case KEY_DOT: return '.';
    case KEY_MINUS: return shift ? '_' : '-';
    default: return '\0';
    }
}

static void cycle_window(Desktop *d)
{
    if (!d->wm.count) return;
    int current = d->wm.focused_id;
    for (size_t i = 0; i < d->wm.count; i++) {
        if (d->wm.z_order[i] != current) continue;
        int next = d->wm.z_order[(i + 1) % d->wm.count];
        (void)neko_wm_restore(&d->wm, next);
        return;
    }
    (void)neko_wm_restore(&d->wm, d->wm.z_order[0]);
}

static void file_selection_step(Desktop *d, int direction)
{
    if (!d->files_ready || d->files.entry_count == 0) return;
    if (!d->has_selection) select_file(d, 0);
    else if (direction < 0 && d->selected_file > 0)
        select_file(d, d->selected_file - 1);
    else if (direction > 0 && d->selected_file + 1 < d->files.entry_count)
        select_file(d, d->selected_file + 1);
}

static void keyboard_press(Desktop *d, unsigned code)
{
    if (d->edit_mode != EDIT_NONE) {
        if (code == KEY_ESC) {
            d->edit_mode = EDIT_NONE;
            snprintf(d->message, sizeof d->message, "CANCELLED");
        } else if (code == KEY_ENTER || code == KEY_KPENTER) {
            submit_edit(d);
        } else if (code == KEY_BACKSPACE) {
            size_t length = strlen(d->edit_name);
            if (length) d->edit_name[length - 1] = '\0';
        } else {
            char ch = key_character(code, d->shift_down);
            size_t length = strlen(d->edit_name);
            if (ch && length + 1 < sizeof d->edit_name) {
                d->edit_name[length] = ch;
                d->edit_name[length + 1] = '\0';
            }
        }
        return;
    }
    if (code == KEY_ESC) {
        if (d->show_preview) d->show_preview = 0;
        else if (d->wm.focused_id) close_app(d, d->wm.focused_id);
        else stop_requested = 1;
        return;
    }
    if (code == KEY_TAB) { cycle_window(d); return; }
    if (code == KEY_F) { open_app(d, APP_FILES); return; }
    if (code == KEY_S) { open_app(d, APP_SYSTEM); return; }
    if (code == KEY_A) { open_app(d, APP_ABOUT); return; }
    if (code == KEY_H) { open_app(d, APP_HELP); return; }
    if (d->wm.focused_id != d->app_ids[APP_FILES]) return;
    if (code == KEY_N) start_edit(d, EDIT_CREATE);
    else if (code == KEY_M) start_edit(d, EDIT_MKDIR);
    else if (code == KEY_R) start_edit(d, EDIT_RENAME);
    else if (code == KEY_U || code == KEY_LEFT) file_up(d);
    else if (code == KEY_UP) file_selection_step(d, -1);
    else if (code == KEY_DOWN) file_selection_step(d, 1);
    else if (code == KEY_ENTER || code == KEY_KPENTER || code == KEY_RIGHT)
        open_selected_file(d);
}

static void file_click(Desktop *d, const NekoWindow *w, int x, int y)
{
    int local_x = x - w->x, local_y = y - w->y;
    if (local_y >= 38 && local_y < 64) {
        if (local_x >= 14 && local_x < 57) file_up(d);
        else if (local_x >= 63 && local_x < 129) start_edit(d, EDIT_CREATE);
        else if (local_x >= 135 && local_x < 207) start_edit(d, EDIT_MKDIR);
        else if (local_x >= 213 && local_x < 293) start_edit(d, EDIT_RENAME);
        return;
    }
    if (!d->files_ready || d->show_preview) {
        if (d->show_preview) d->show_preview = 0;
        return;
    }
    int list_width = w->width >= 540 ? 250 : w->width - 28;
    int row = (local_y - 112) / 28;
    if (local_y < 112 || local_x < 13 || local_x >= 13 + list_width ||
        row < 0 || row >= files_rows(w)) return;
    size_t index = d->file_scroll + (size_t)row;
    if (index >= d->files.entry_count) return;
    if (d->has_selection && d->selected_file == index) open_selected_file(d);
    else select_file(d, index);
}

static void mouse_press(Desktop *d)
{
    int x = d->mouse_x, y = d->mouse_y;
    d->mouse_down = 1;
    if (y >= d->wm.screen_height - 45) {
        if (x >= 11 && x < 75) { open_app(d, APP_FILES); return; }
        int task_width = (d->wm.screen_width - 95) / APP_COUNT;
        if (task_width > 140) task_width = 140;
        int app = task_width > 0 ? (x - 85) / task_width : -1;
        if (x >= 85 && app >= 0 && app < APP_COUNT &&
            d->app_ids[app]) open_app(d, (enum App)app);
        return;
    }
    NekoWindowHit hit = neko_wm_hit_test(&d->wm, x, y);
    if (hit.id) {
        const NekoWindow *w = neko_wm_get(&d->wm, hit.id);
        if (hit.part == NEKO_WM_HIT_CLOSE) {
            close_app(d, hit.id);
            return;
        }
        if (hit.part == NEKO_WM_HIT_TITLE &&
            x >= w->x + w->width - 53 && x < w->x + w->width - 29) {
            (void)neko_wm_minimize(&d->wm, hit.id);
            return;
        }
        int offset_x = x - w->x, offset_y = y - w->y;
        (void)neko_wm_focus(&d->wm, hit.id);
        if (hit.part == NEKO_WM_HIT_TITLE) {
            d->drag_id = hit.id;
            d->drag_offset_x = offset_x;
            d->drag_offset_y = offset_y;
        } else if (app_for_window(d, hit.id) == APP_FILES) {
            file_click(d, w, x, y);
        }
        return;
    }
    if (y >= 68 && y < 139) {
        int app = (x - 24) / 100;
        if (x >= 24 && app >= 0 && app < APP_COUNT &&
            x < 24 + app * 100 + 84)
            open_app(d, (enum App)app);
    }
}

static int move_pointer(Desktop *d, int dx, int dy)
{
    int64_t x = (int64_t)d->mouse_x + dx;
    int64_t y = (int64_t)d->mouse_y + dy;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x >= d->wm.screen_width) x = d->wm.screen_width - 1;
    if (y >= d->wm.screen_height) y = d->wm.screen_height - 1;
    d->mouse_x = (int)x;
    d->mouse_y = (int)y;
    d->mouse_present = 1;
    if (d->mouse_down && d->drag_id)
        (void)neko_wm_move_to(&d->wm, d->drag_id,
                             d->mouse_x - d->drag_offset_x,
                             d->mouse_y - d->drag_offset_y);
    return 1;
}

static int absolute_position(int value, const struct input_absinfo *axis,
                             int screen_size)
{
    int64_t position = value;
    if (position < axis->minimum) position = axis->minimum;
    if (position > axis->maximum) position = axis->maximum;
    return (int)((position - axis->minimum) * (screen_size - 1) /
                 ((int64_t)axis->maximum - axis->minimum));
}


static int write_preview(const Canvas *c, const char *path)
{
    FILE *out = fopen(path, "wb");
    if (!out) { perror(path); return -1; }
    fprintf(out, "P6\n%d %d\n255\n", c->width, c->height);
    for (int y = 0; y < c->height; y++) {
        for (int x = 0; x < c->width; x++) {
            uint32_t pixel = c->pixels[(size_t)y * c->width + x];
            unsigned char rgb[3] = {
                (unsigned char)(pixel >> 16),
                (unsigned char)(pixel >> 8),
                (unsigned char)pixel
            };
            if (fwrite(rgb, 1, 3, out) != 3) {
                perror("write preview");
                fclose(out);
                return -1;
            }
        }
    }
    if (fclose(out) != 0) { perror("close preview"); return -1; }
    return 0;
}

int main(int argc, char **argv)
{
    int once = 0;
    const char *preview = NULL;
    if (argc == 2 && (strcmp(argv[1], "--once") == 0 ||
                      strcmp(argv[1], "--self-test") == 0)) once = 1;
    else if (argc == 3 && strcmp(argv[1], "--preview") == 0) preview = argv[2];
    else if (argc != 1) {
        fprintf(stderr, "Usage: neko-desktop [--once | --self-test | --preview FILE.ppm]\n");
        return 2;
    }

    Framebuffer fb;
    int width = 1024, height = 768;
    if (!preview) {
        if (open_framebuffer(&fb) < 0) return 1;
        width = (int)fb.var.xres;
        height = (int)fb.var.yres;
    }
    Canvas c = {width, height, calloc((size_t)width * height, sizeof(uint32_t))};
    if (!c.pixels) {
        perror("allocate canvas");
        if (!preview) { munmap(fb.mapping, fb.length); close(fb.fd); }
        return 1;
    }
    Desktop *d = calloc(1, sizeof *d);
    if (!d) {
        perror("allocate desktop");
        free(c.pixels);
        if (!preview) { munmap(fb.mapping, fb.length); close(fb.fd); }
        return 1;
    }
    desktop_init(d, width, height);
    if (preview) {
        open_app(d, APP_FILES);
        open_app(d, APP_SYSTEM);
    }
    render(&c, d);
    if (preview) {
        int result = write_preview(&c, preview);
        desktop_close(d);
        free(d);
        free(c.pixels);
        return result == 0 ? 0 : 1;
    }
    int tty = once ? -1 : open("/dev/tty0", O_RDWR | O_CLOEXEC);
    int old_mode = KD_TEXT;
    int graphics_mode = 0;
    if (tty >= 0 && ioctl(tty, KDGETMODE, &old_mode) == 0 &&
        ioctl(tty, KDSETMODE, KD_GRAPHICS) == 0)
        graphics_mode = 1;
    flush_framebuffer(&c, &fb);
    printf("NEKO_DESKTOP_FRAME_READY width=%d height=%d depth=%u\n",
           width, height, fb.var.bits_per_pixel);
    fflush(stdout);
    if (once) {
        desktop_close(d);
        free(d);
        free(c.pixels);
        munmap(fb.mapping, fb.length);
        close(fb.fd);
        return 0;
    }
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = on_signal;
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    Inputs inputs;
    open_inputs(&inputs);
    int absolute_seen = 0;
    if (inputs.count > 0) {
        puts("NEKO_DESKTOP_INPUT_READY");
        fflush(stdout);
    } else
        fprintf(stderr, "No input devices; press Ctrl+C in the serial console to exit.\n");
    while (!stop_requested) {
        struct pollfd pfds[MAX_INPUTS];
        for (size_t i = 0; i < inputs.count; i++) {
            pfds[i].fd = inputs.device[i].fd;
            pfds[i].events = POLLIN;
            pfds[i].revents = 0;
        }
        int count = poll(pfds, inputs.count, 250);
        if (count < 0) {
            if (errno == EINTR) continue;
            perror("poll input");
            break;
        }
        int changed = 0;
        for (size_t i = 0; i < inputs.count; i++) {
            if (!(pfds[i].revents & POLLIN)) continue;
            struct input_event event;
            while (read(inputs.device[i].fd, &event, sizeof event) ==
                   sizeof event) {
                if (event.type == EV_REL &&
                    (event.code == REL_X || event.code == REL_Y)) {
                    changed |= move_pointer(d,
                        event.code == REL_X ? event.value : 0,
                        event.code == REL_Y ? event.value : 0);
                } else if (event.type == EV_ABS &&
                           inputs.device[i].absolute &&
                           (event.code == ABS_X || event.code == ABS_Y)) {
                    int x = event.code == ABS_X ?
                        absolute_position(event.value, &inputs.device[i].abs_x,
                                          d->wm.screen_width) : d->mouse_x;
                    int y = event.code == ABS_Y ?
                        absolute_position(event.value, &inputs.device[i].abs_y,
                                          d->wm.screen_height) : d->mouse_y;
                    changed |= move_pointer(d, x - d->mouse_x, y - d->mouse_y);
                    if (!absolute_seen) {
                        puts("NEKO_DESKTOP_POINTER_READY");
                        fflush(stdout);
                        absolute_seen = 1;
                    }
                } else if (event.type == EV_REL && event.code == REL_WHEEL &&
                           d->wm.focused_id == d->app_ids[APP_FILES]) {
                    if (event.value < 0 && d->file_scroll + 1 < d->files.entry_count)
                        d->file_scroll++;
                    else if (event.value > 0 && d->file_scroll > 0)
                        d->file_scroll--;
                    changed = 1;
                } else if (event.type == EV_KEY &&
                           (event.code == KEY_LEFTSHIFT ||
                            event.code == KEY_RIGHTSHIFT)) {
                    d->shift_down = event.value != 0;
                } else if (event.type == EV_KEY && event.code == BTN_LEFT) {
                    if (event.value == 1) mouse_press(d);
                    else if (event.value == 0) {
                        d->mouse_down = 0;
                        d->drag_id = 0;
                    }
                    changed = 1;
                } else if (event.type == EV_KEY && event.value == 1) {
                    keyboard_press(d, event.code);
                    changed = 1;
                }
            }
        }
        if (changed && !stop_requested) {
            render(&c, d);
            flush_framebuffer(&c, &fb);
        }
    }
    close_inputs(&inputs);
    if (graphics_mode) ioctl(tty, KDSETMODE, old_mode);
    if (tty >= 0) close(tty);
    desktop_close(d);
    free(d);
    free(c.pixels);
    munmap(fb.mapping, fb.length);
    close(fb.fd);
    puts("NEKO_DESKTOP_EXITED");
    return 0;
}
