#include "../rootfs/usr/bin/neko-windows.h"

#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    NekoWindowManager wm;
    neko_wm_init(&wm, 800, 600);
    assert(wm.count == 0 && wm.focused_id == 0);
    assert(neko_wm_create(&wm, "invalid", 0, 0, 0, 50) == 0);

    int first = neko_wm_create(&wm, "Files", 10, 20, 300, 200);
    int second = neko_wm_create(&wm, "Settings", 100, 100, 250, 150);
    assert(first > 0 && second > first && wm.focused_id == second);
    assert(neko_wm_at_z(&wm, 0)->id == first);
    assert(neko_wm_at_z(&wm, 1)->id == second);
    assert(neko_wm_hit_test(&wm, 105, 105).id == second);
    assert(neko_wm_hit_test(&wm, 105, 105).part == NEKO_WM_HIT_TITLE);
    assert(neko_wm_hit_test(&wm, 340, 105).part == NEKO_WM_HIT_CLOSE);
    assert(neko_wm_hit_test(&wm, 200, 150).part == NEKO_WM_HIT_CONTENT);
    assert(neko_wm_hit_test(&wm, 799, 599).part == NEKO_WM_HIT_NONE);

    assert(neko_wm_focus(&wm, first));
    assert(neko_wm_at_z(&wm, 1)->id == first && wm.focused_id == first);
    assert(neko_wm_hit_test(&wm, 110, 110).id == first);
    assert(neko_wm_minimize(&wm, first));
    assert(wm.focused_id == second);
    assert(!neko_wm_focus(&wm, first));
    assert(neko_wm_hit_test(&wm, 110, 110).id == second);
    assert(neko_wm_restore(&wm, first));
    assert(wm.focused_id == first && !neko_wm_get(&wm, first)->minimized);
    assert(neko_wm_hit_test(&wm, 110, 110).id == first);

    assert(neko_wm_move_to(&wm, first, INT_MAX, INT_MIN));
    assert(neko_wm_get(&wm, first)->x == 500);
    assert(neko_wm_get(&wm, first)->y == 0);
    neko_wm_resize_screen(&wm, 160, 100);
    assert(neko_wm_get(&wm, first)->width == 160);
    assert(neko_wm_get(&wm, first)->height == 100);
    assert(neko_wm_get(&wm, first)->x == 0 && neko_wm_get(&wm, first)->y == 0);

    assert(neko_wm_close(&wm, first));
    assert(wm.focused_id == second);
    assert(neko_wm_get(&wm, first) == NULL);
    assert(!neko_wm_close(&wm, first));
    assert(neko_wm_close(&wm, second));
    assert(wm.count == 0 && wm.focused_id == 0);

    char long_title[128];
    memset(long_title, 'X', sizeof long_title);
    long_title[sizeof long_title - 1] = '\0';
    for (int i = 0; i < NEKO_WM_MAX_WINDOWS; i++) {
        int id = neko_wm_create(&wm, long_title, 0, 0, 100, 50);
        assert(id > 0);
        assert(strlen(neko_wm_get(&wm, id)->title) == NEKO_WM_TITLE_MAX);
    }
    assert(neko_wm_create(&wm, "overflow", 0, 0, 100, 50) == 0);
    assert(wm.count == NEKO_WM_MAX_WINDOWS);

    puts("neko windows model: OK");
    return 0;
}
