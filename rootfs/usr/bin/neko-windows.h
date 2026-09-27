#ifndef NEKO_WINDOWS_H
#define NEKO_WINDOWS_H

#include <stdbool.h>
#include <stddef.h>

#define NEKO_WM_MAX_WINDOWS 8
#define NEKO_WM_TITLE_MAX 47
#define NEKO_WM_TITLE_HEIGHT 28
#define NEKO_WM_CLOSE_WIDTH 26

/* Window IDs are positive and stay valid until that window is closed. */
typedef struct {
    int id;
    int x;
    int y;
    int width;
    int height;
    bool minimized;
    char title[NEKO_WM_TITLE_MAX + 1];
} NekoWindow;

/* z_order[0] is the backmost window; z_order[count - 1] is the frontmost. */
typedef struct {
    NekoWindow windows[NEKO_WM_MAX_WINDOWS];
    int z_order[NEKO_WM_MAX_WINDOWS];
    size_t count;
    int focused_id; /* 0 if no visible window has focus. */
    int next_id;
    int screen_width;
    int screen_height;
} NekoWindowManager;

typedef enum {
    NEKO_WM_HIT_NONE,
    NEKO_WM_HIT_TITLE,
    NEKO_WM_HIT_CLOSE,
    NEKO_WM_HIT_CONTENT
} NekoWindowHitPart;

typedef struct {
    int id; /* 0 for no hit. */
    NekoWindowHitPart part;
} NekoWindowHit;

void neko_wm_init(NekoWindowManager *wm, int screen_width, int screen_height);
void neko_wm_resize_screen(NekoWindowManager *wm, int screen_width, int screen_height);
int neko_wm_create(NekoWindowManager *wm, const char *title,
                   int x, int y, int width, int height);
bool neko_wm_close(NekoWindowManager *wm, int id);
bool neko_wm_focus(NekoWindowManager *wm, int id);
bool neko_wm_minimize(NekoWindowManager *wm, int id);
bool neko_wm_restore(NekoWindowManager *wm, int id);
bool neko_wm_move_to(NekoWindowManager *wm, int id, int x, int y);
const NekoWindow *neko_wm_get(const NekoWindowManager *wm, int id);
const NekoWindow *neko_wm_at_z(const NekoWindowManager *wm, size_t index);
NekoWindowHit neko_wm_hit_test(const NekoWindowManager *wm, int x, int y);

#endif
