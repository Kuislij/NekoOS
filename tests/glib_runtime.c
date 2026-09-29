/* Exercise GLib, GObject, and GIO through the packaged shared libraries. */
#include <gio/gio.h>
#include <glib-object.h>
#include <glib.h>
#include <stdio.h>

int main(void)
{
    GVariant *value = g_variant_ref_sink(g_variant_new_string("neko"));
    if (g_strcmp0(g_variant_get_string(value, NULL), "neko") != 0) {
        g_variant_unref(value);
        return 1;
    }
    g_variant_unref(value);

    GObject *object = g_object_new(G_TYPE_OBJECT, NULL);
    if (object == NULL || !G_IS_OBJECT(object)) {
        if (object != NULL)
            g_object_unref(object);
        return 1;
    }
    g_object_unref(object);

    GInputStream *stream = g_memory_input_stream_new_from_data("gio", 3, NULL);
    char buffer[4] = { 0 };
    GError *error = NULL;
    gssize count = g_input_stream_read(stream, buffer, 3, NULL, &error);
    g_object_unref(stream);
    if (count != 3 || g_strcmp0(buffer, "gio") != 0 || error != NULL) {
        if (error != NULL) {
            fprintf(stderr, "GIO read failed: %s\n", error->message);
            g_error_free(error);
        }
        return 1;
    }
    puts("GLIB_RUNTIME_READY");
    return 0;
}
