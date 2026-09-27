#include "neko-windows.h"

#include <limits.h>
#include <string.h>

static int positive_dimension(int value)
{
    return value > 0 ? value : 1;
}

static int clamp(int value, int minimum, int maximum)
{
    if (value < minimum) return minimum;
    if (value > maximum) return maximum;
    return value;
}

static int window_index(const NekoWindowManager *wm, int id)
{
    if (id <= 0) return -1;
    for (size_t i = 0; i < wm->count; i++)
        if (wm->windows[i].id == id) return (int)i;
    return -1;
}

static void keep_on_screen(NekoWindowManager *wm, NekoWindow *window)
{
    window->width = clamp(window->width, 1, wm->screen_width);
    window->height = clamp(window->height, 1, wm->screen_height);
    window->x = clamp(window->x, 0, wm->screen_width - window->width);
    window->y = clamp(window->y, 0, wm->screen_height - window->height);
}

static void bring_to_front(NekoWindowManager *wm, int id)
{
    size_t z = 0;
    while (z < wm->count && wm->z_order[z] != id) z++;
    if (z == wm->count) return;
    for (; z + 1 < wm->count; z++) wm->z_order[z] = wm->z_order[z + 1];
    wm->z_order[wm->count - 1] = id;
}

static int frontmost_visible(const NekoWindowManager *wm)
{
    for (size_t z = wm->count; z > 0; z--) {
        const NekoWindow *window = neko_wm_get(wm, wm->z_order[z - 1]);
        if (window && !window->minimized) return window->id;
    }
    return 0;
}

static int next_window_id(NekoWindowManager *wm)
{
    int candidate = wm->next_id;
    if (candidate <= 0) candidate = 1;
    for (;;) {
        int next = candidate == INT_MAX ? 1 : candidate + 1;
        if (window_index(wm, candidate) < 0) {
            wm->next_id = next;
            return candidate;
        }
        candidate = next;
    }
}

void neko_wm_init(NekoWindowManager *wm, int screen_width, int screen_height)
{
    memset(wm, 0, sizeof *wm);
    wm->next_id = 1;
    wm->screen_width = positive_dimension(screen_width);
    wm->screen_height = positive_dimension(screen_height);
}

void neko_wm_resize_screen(NekoWindowManager *wm, int screen_width, int screen_height)
{
    wm->screen_width = positive_dimension(screen_width);
    wm->screen_height = positive_dimension(screen_height);
    for (size_t i = 0; i < wm->count; i++) keep_on_screen(wm, &wm->windows[i]);
}

int neko_wm_create(NekoWindowManager *wm, const char *title,
                   int x, int y, int width, int height)
{
    if (wm->count == NEKO_WM_MAX_WINDOWS || width <= 0 || height <= 0) return 0;
    NekoWindow *window = &wm->windows[wm->count];
    memset(window, 0, sizeof *window);
    window->id = next_window_id(wm);
    window->x = x;
    window->y = y;
    window->width = width;
    window->height = height;
    if (title) {
        strncpy(window->title, title, NEKO_WM_TITLE_MAX);
        window->title[NEKO_WM_TITLE_MAX] = '\0';
    }
    keep_on_screen(wm, window);
    wm->z_order[wm->count++] = window->id;
    wm->focused_id = window->id;
    return window->id;
}

bool neko_wm_close(NekoWindowManager *wm, int id)
{
    int index = window_index(wm, id);
    if (index < 0) return false;
    size_t z = 0;
    while (wm->z_order[z] != id) z++;
    for (; z + 1 < wm->count; z++) wm->z_order[z] = wm->z_order[z + 1];
    for (size_t i = (size_t)index; i + 1 < wm->count; i++)
        wm->windows[i] = wm->windows[i + 1];
    wm->count--;
    memset(&wm->windows[wm->count], 0, sizeof wm->windows[wm->count]);
    wm->z_order[wm->count] = 0;
    if (wm->focused_id == id) wm->focused_id = frontmost_visible(wm);
    return true;
}

bool neko_wm_focus(NekoWindowManager *wm, int id)
{
    int index = window_index(wm, id);
    if (index < 0 || wm->windows[index].minimized) return false;
    bring_to_front(wm, id);
    wm->focused_id = id;
    return true;
}

bool neko_wm_minimize(NekoWindowManager *wm, int id)
{
    int index = window_index(wm, id);
    if (index < 0) return false;
    wm->windows[index].minimized = true;
    if (wm->focused_id == id) wm->focused_id = frontmost_visible(wm);
    return true;
}

bool neko_wm_restore(NekoWindowManager *wm, int id)
{
    int index = window_index(wm, id);
    if (index < 0) return false;
    wm->windows[index].minimized = false;
    return neko_wm_focus(wm, id);
}

bool neko_wm_move_to(NekoWindowManager *wm, int id, int x, int y)
{
    int index = window_index(wm, id);
    if (index < 0) return false;
    wm->windows[index].x = x;
    wm->windows[index].y = y;
    keep_on_screen(wm, &wm->windows[index]);
    return true;
}

const NekoWindow *neko_wm_get(const NekoWindowManager *wm, int id)
{
    int index = window_index(wm, id);
    return index < 0 ? NULL : &wm->windows[index];
}

const NekoWindow *neko_wm_at_z(const NekoWindowManager *wm, size_t index)
{
    if (index >= wm->count) return NULL;
    return neko_wm_get(wm, wm->z_order[index]);
}

NekoWindowHit neko_wm_hit_test(const NekoWindowManager *wm, int x, int y)
{
    NekoWindowHit hit = {0, NEKO_WM_HIT_NONE};
    for (size_t z = wm->count; z > 0; z--) {
        const NekoWindow *window = neko_wm_at_z(wm, z - 1);
        if (window->minimized || x < window->x || y < window->y) continue;
        int local_x = x - window->x;
        int local_y = y - window->y;
        if (local_x >= window->width || local_y >= window->height) continue;
        hit.id = window->id;
        if (local_y < NEKO_WM_TITLE_HEIGHT) {
            hit.part = local_x >= window->width - NEKO_WM_CLOSE_WIDTH
                       ? NEKO_WM_HIT_CLOSE : NEKO_WM_HIT_TITLE;
        } else {
            hit.part = NEKO_WM_HIT_CONTENT;
        }
        return hit;
    }
    return hit;
}
