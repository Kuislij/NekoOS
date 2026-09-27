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
    int fd[MAX_INPUTS];
    size_t count;
} Inputs;

enum Page { PAGE_HOME, PAGE_ABOUT, PAGE_KEYS, PAGE_COUNT };

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
    {'/',{1,1,2,4,8,16,16}}, {'>',{16,8,4,2,4,8,16}},
    {'?',{14,17,1,2,4,0,4}},
};

static const uint8_t *glyph_for(char ch)
{
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

static int sidebar_width(const Canvas *c)
{
    int width = c->width / 5;
    if (width < 142) width = 142;
    if (width > 230) width = 230;
    return width;
}

static void draw_sidebar(Canvas *c, enum Page page)
{
    int sw = sidebar_width(c);
    static const char *labels[] = { "HOME", "ABOUT", "KEYS" };
    fill_rect(c, 0, 60, sw, c->height - 60, C_BAR);
    for (int i = 0; i < PAGE_COUNT; i++) {
        int y = 112 + i * 67;
        if (i == (int)page) round_rect(c, 12, y - 12, sw - 24, 48, 11, C_PANEL_LIGHT);
        if (i == (int)page) round_rect(c, 12, y - 12, 4, 48, 2, C_ACCENT);
        draw_text(c, 27, y, 2, i == (int)page ? C_TEXT : C_MUTED, labels[i]);
    }
    if (c->height > 500) {
        draw_text(c, 25, c->height - 88, 1, C_MUTED, "FIRST DESKTOP");
        draw_text(c, 25, c->height - 70, 1, C_MUTED, "PROTOTYPE");
    }
}

static void draw_home(Canvas *c, int x, int width)
{
    draw_text(c, x, 98, 2, C_ACCENT, "WELCOME TO");
    draw_text(c, x, 130, 5, C_TEXT, "NEKOOS");
    draw_text(c, x, 183, 2, C_MUTED, "YOUR SYSTEM IS READY");
    int card_y = c->height > 650 ? 247 : 225;
    int card_h = c->height - card_y - 88;
    if (card_h > 325) card_h = 325;
    if (card_h < 160) card_h = 160;
    round_rect(c, x, card_y, width, card_h, 18, C_PANEL);
    draw_cat(c, x + 28, card_y + 30, 72);
    int text_x = x + (width > 520 ? 130 : 112);
    draw_text(c, text_x, card_y + 35, 2, C_TEXT, "HELLO NEKO");
    draw_text(c, text_x, card_y + 66, 1, C_MUTED, "LINUX BASED OS");
    if (card_h > 210) {
        fill_rect(c, x + 27, card_y + 136, width - 54, 1, C_PANEL_LIGHT);
        draw_text(c, x + 28, card_y + 160, 2, C_ACCENT, "A  ABOUT");
        draw_text(c, x + 28, card_y + 199, 2, C_PINK, "K  KEYBOARD");
        if (card_h > 275)
            draw_text(c, x + 28, card_y + 243, 1, C_MUTED,
                      "CLICK THE MENU OR USE KEYS");
    }
}

static void draw_about(Canvas *c, int x, int width)
{
    draw_text(c, x, 98, 3, C_TEXT, "ABOUT NEKOOS");
    draw_text(c, x, 139, 2, C_MUTED, "A SMALL LINUX SYSTEM");
    round_rect(c, x, 204, width, c->height > 560 ? 300 : 205, 18, C_PANEL);
    draw_cat(c, x + 28, 231, 72);
    draw_text(c, x + 121, 238, 2, C_ACCENT, "NEKOOS");
    draw_text(c, x + 121, 270, 1, C_MUTED, "GRAPHICAL PREVIEW");
    fill_rect(c, x + 28, 331, width - 56, 1, C_PANEL_LIGHT);
    draw_text(c, x + 28, 352, 2, C_TEXT, "LINUX KERNEL");
    draw_text(c, x + 28, 385, 2, C_TEXT, "FRAMEBUFFER UI");
    if (c->height > 560)
        draw_text(c, x + 28, 433, 1, C_MUTED,
                  "NEXT: SESSIONS AND WINDOWS");
}

static void draw_keys(Canvas *c, int x, int width)
{
    draw_text(c, x, 98, 3, C_TEXT, "KEYBOARD");
    draw_text(c, x, 139, 2, C_MUTED, "CONTROLS");
    round_rect(c, x, 204, width, c->height > 560 ? 300 : 205, 18, C_PANEL);
    draw_text(c, x + 28, 236, 2, C_ACCENT, "H  HOME");
    draw_text(c, x + 28, 277, 2, C_ACCENT, "A  ABOUT");
    draw_text(c, x + 28, 318, 2, C_ACCENT, "K  KEYS");
    draw_text(c, x + 28, 359, 2, C_PINK, "ESC  EXIT");
    if (c->height > 560) {
        fill_rect(c, x + 28, 408, width - 56, 1, C_PANEL_LIGHT);
        draw_text(c, x + 28, 435, 1, C_MUTED,
                  "ARROW KEYS ALSO WORK");
    }
}

static void draw_cursor(Canvas *c, int x, int y)
{
    fill_rect(c, x - 1, y - 1, 3, 19, C_BG);
    fill_rect(c, x - 1, y - 1, 17, 3, C_BG);
    fill_rect(c, x, y, 1, 17, C_TEXT);
    fill_rect(c, x, y, 15, 1, C_TEXT);
    for (int i = 0; i < 10; i++) fill_rect(c, x + i, y + i, 2, 2, C_TEXT);
}

static void render(Canvas *c, enum Page page, int mouse_x, int mouse_y,
                   int mouse_present)
{
    fill_rect(c, 0, 0, c->width, c->height, C_BG);
    fill_rect(c, 0, 0, c->width, 60, C_BAR);
    draw_cat(c, 17, 9, 37);
    draw_text(c, 67, 21, 2, C_TEXT, "NEKOOS");
    if (c->width >= 800)
        draw_text(c, c->width - 211, 25, 1, C_ACCENT, "GRAPHICAL PREVIEW");
    draw_sidebar(c, page);
    int x = sidebar_width(c) + 28;
    int width = c->width - x - 28;
    if (page == PAGE_HOME) draw_home(c, x, width);
    else if (page == PAGE_ABOUT) draw_about(c, x, width);
    else draw_keys(c, x, width);
    fill_rect(c, sidebar_width(c), c->height - 53,
              c->width - sidebar_width(c), 53, C_BAR);
    draw_text(c, x, c->height - 34, 1, C_MUTED,
              "H HOME  A ABOUT  K KEYS  ESC EXIT");
    if (mouse_present) draw_cursor(c, mouse_x, mouse_y);
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
        if (fd >= 0) inputs->fd[inputs->count++] = fd;
    }
}

static void close_inputs(Inputs *inputs)
{
    for (size_t i = 0; i < inputs->count; i++) close(inputs->fd[i]);
}

static enum Page clicked_page(const Canvas *c, int x, int y, enum Page previous)
{
    if (x >= sidebar_width(c)) return previous;
    for (int i = 0; i < PAGE_COUNT; i++)
        if (y >= 100 + i * 67 && y < 148 + i * 67)
            return (enum Page)i;
    return previous;
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
    render(&c, PAGE_HOME, 0, 0, 0);
    if (preview) {
        int result = write_preview(&c, preview);
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
    if (inputs.count == 0)
        fprintf(stderr, "No input devices; press Ctrl+C in the serial console to exit.\n");
    enum Page page = PAGE_HOME;
    int mouse_x = width / 2, mouse_y = height / 2, mouse_present = 0;
    while (!stop_requested) {
        struct pollfd pfds[MAX_INPUTS];
        for (size_t i = 0; i < inputs.count; i++) {
            pfds[i].fd = inputs.fd[i];
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
            while (read(inputs.fd[i], &event, sizeof event) == sizeof event) {
                if (event.type == EV_REL && event.code == REL_X) {
                    mouse_x += event.value;
                    if (mouse_x < 0) mouse_x = 0;
                    if (mouse_x >= width) mouse_x = width - 1;
                    mouse_present = changed = 1;
                } else if (event.type == EV_REL && event.code == REL_Y) {
                    mouse_y += event.value;
                    if (mouse_y < 0) mouse_y = 0;
                    if (mouse_y >= height) mouse_y = height - 1;
                    mouse_present = changed = 1;
                } else if (event.type == EV_KEY && event.value == 1) {
                    enum Page next = page;
                    switch (event.code) {
                    case KEY_ESC: stop_requested = 1; break;
                    case KEY_H: next = PAGE_HOME; break;
                    case KEY_A: next = PAGE_ABOUT; break;
                    case KEY_K: next = PAGE_KEYS; break;
                    case KEY_UP: next = (page + PAGE_COUNT - 1) % PAGE_COUNT; break;
                    case KEY_DOWN: next = (page + 1) % PAGE_COUNT; break;
                    case BTN_LEFT:
                        next = clicked_page(&c, mouse_x, mouse_y, page);
                        break;
                    default: break;
                    }
                    if (next != page) { page = next; changed = 1; }
                }
            }
        }
        if (changed && !stop_requested) {
            render(&c, page, mouse_x, mouse_y, mouse_present);
            flush_framebuffer(&c, &fb);
        }
    }
    close_inputs(&inputs);
    if (graphics_mode) ioctl(tty, KDSETMODE, old_mode);
    if (tty >= 0) close(tty);
    free(c.pixels);
    munmap(fb.mapping, fb.length);
    close(fb.fd);
    puts("NEKO_DESKTOP_EXITED");
    return 0;
}
