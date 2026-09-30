#include <atk/atk.h>
#include <atk-bridge.h>
#include <atspi/atspi.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    AtkObject *object = g_object_new(ATK_TYPE_NO_OP_OBJECT, NULL);
    AtkStateSet *states = atk_state_set_new();
    if (!object || !states || !g_type_is_a(atspi_accessible_get_type(), G_TYPE_OBJECT))
        return 1;
    atk_object_set_name(object, "NekoOS accessibility");
    atk_object_set_role(object, ATK_ROLE_APPLICATION);
    atk_state_set_add_state(states, ATK_STATE_ENABLED);
    if (strcmp(atk_object_get_name(object), "NekoOS accessibility") ||
        atk_object_get_role(object) != ATK_ROLE_APPLICATION ||
        !atk_state_set_contains_state(states, ATK_STATE_ENABLED))
        return 2;
    atk_bridge_adaptor_cleanup();
    g_object_unref(states);
    g_object_unref(object);
    printf("ATSPI_SMOKE_OK: ATK %s, AT-SPI %d.%d.%d\n", atk_get_version(),
           ATSPI_MAJOR_VERSION, ATSPI_MINOR_VERSION, ATSPI_MICRO_VERSION);
    return 0;
}
