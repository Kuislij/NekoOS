/* NekoOS GTK3 welcome window and persistent text note. */
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    GtkWidget *window;
    GtkWidget *heading;
    GtkWidget *text_view;
    GtkWidget *save_button;
    GtkWidget *status;
    GtkWidget *image;
    gchar *note_path;
    gboolean self_test;
    gboolean save_ok;
    gboolean mapped_reported;
    guint draw_count;
    guint readiness_retries;
    int exit_status;
} Welcome;

static void show_error(Welcome *app, const char *operation, GError *error)
{
    gchar *message = g_strdup_printf("%s: %s", operation,
                                    error ? error->message : "неизвестная ошибка");
    gtk_label_set_text(GTK_LABEL(app->status), message);
    g_free(message);
    g_clear_error(&error);
}

static gboolean load_note(Welcome *app)
{
    GFile *file = g_file_new_for_path(app->note_path);
    GError *error = NULL;
    gchar *contents = NULL;
    gsize length = 0;
    gboolean loaded = g_file_load_contents(file, NULL, &contents, &length,
                                          NULL, &error);
    g_object_unref(file);
    if (!loaded) {
        if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND)) {
            g_clear_error(&error);
            gtk_label_set_text(GTK_LABEL(app->status),
                               "Напишите заметку и нажмите «Сохранить».");
        } else {
            show_error(app, "Не удалось открыть заметку", error);
        }
        return FALSE;
    }
    if (length > G_MAXINT || !g_utf8_validate(contents, (gssize)length, NULL)) {
        gtk_label_set_text(GTK_LABEL(app->status),
                           "Не удалось открыть заметку: нужен текст в UTF-8.");
        g_free(contents);
        return FALSE;
    }
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(app->text_view));
    gtk_text_buffer_set_text(buffer, contents, (gint)length);
    gtk_text_buffer_set_modified(buffer, FALSE);
    gtk_label_set_text(GTK_LABEL(app->status), "Открыта сохранённая заметка.");
    g_free(contents);
    return TRUE;
}

static void save_note(GtkButton *button, gpointer data)
{
    Welcome *app = data;
    GError *error = NULL;
    GFile *file = g_file_new_for_path(app->note_path);
    GFile *directory = g_file_get_parent(file);
    app->save_ok = FALSE;
    (void)button;

    if (!directory) {
        gtk_label_set_text(GTK_LABEL(app->status),
                           "Не удалось сохранить заметку: неверный путь.");
        g_object_unref(file);
        return;
    }
    if (!g_file_make_directory_with_parents(directory, NULL, &error)) {
        if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_EXISTS)) {
            g_clear_error(&error);
        } else {
            show_error(app, "Не удалось создать папку для заметки", error);
            g_object_unref(directory);
            g_object_unref(file);
            return;
        }
    }
    g_object_unref(directory);

    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(app->text_view));
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    gchar *contents = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
    /* GIO writes a replacement file before committing it to the note path. */
    gboolean saved = g_file_replace_contents(file, contents, strlen(contents),
                                            NULL, FALSE,
                                            G_FILE_CREATE_PRIVATE |
                                            G_FILE_CREATE_REPLACE_DESTINATION,
                                            NULL, NULL, &error);
    g_free(contents);
    g_object_unref(file);
    if (!saved) {
        show_error(app, "Не удалось сохранить заметку", error);
        return;
    }
    app->save_ok = TRUE;
    gtk_text_buffer_set_modified(buffer, FALSE);
    gtk_label_set_text(GTK_LABEL(app->status), "Сохранено. Заметка останется после перезапуска.");
}

static gboolean confirm_close(GtkWidget *window, GdkEvent *event, gpointer data)
{
    Welcome *app = data;
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(app->text_view));
    (void)event;
    if (app->self_test || !gtk_text_buffer_get_modified(buffer))
        return FALSE;

    GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_QUESTION, GTK_BUTTONS_NONE,
        "Сохранить изменения в заметке?");
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog),
                                             "Последние изменения ещё не сохранены.");
    gtk_dialog_add_buttons(GTK_DIALOG(dialog),
                           "Отмена", GTK_RESPONSE_CANCEL,
                           "Не сохранять", GTK_RESPONSE_REJECT,
                           "Сохранить", GTK_RESPONSE_ACCEPT, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(dialog), GTK_RESPONSE_ACCEPT);
    gint response = gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
    if (response == GTK_RESPONSE_REJECT)
        return FALSE;
    if (response == GTK_RESPONSE_ACCEPT) {
        save_note(NULL, app);
        /* A failed save leaves both the note and its error status visible. */
        return !app->save_ok;
    }
    return TRUE;
}

static void request_close(GtkButton *button, gpointer data)
{
    Welcome *app = data;
    (void)button;
    gtk_window_close(GTK_WINDOW(app->window));
}

/* Draw a small document icon, then decode its PNG through GdkPixbuf. */
static GdkPixbuf *make_document_image(GError **error)
{
    GdkPixbuf *source = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 48, 48);
    if (!source)
        return NULL;
    gdk_pixbuf_fill(source, 0x00000000);
    guchar *pixels = gdk_pixbuf_get_pixels(source);
    int stride = gdk_pixbuf_get_rowstride(source);
    for (int y = 5; y < 43; ++y) {
        for (int x = 9; x < 39; ++x) {
            if (y < 13 && x > 30 && x + y > 43)
                continue;
            guchar *pixel = pixels + y * stride + x * 4;
            gboolean line = x >= 15 && x <= 32 &&
                            ((y >= 20 && y <= 22) ||
                             (y >= 28 && y <= 30) ||
                             (y >= 36 && y <= 38));
            pixel[0] = line ? 0x76 : 0xe9;
            pixel[1] = line ? 0x52 : 0xe1;
            pixel[2] = line ? 0xb5 : 0xfa;
            pixel[3] = 0xff;
        }
    }
    gchar *png = NULL;
    gsize png_length = 0;
    if (!gdk_pixbuf_save_to_buffer(source, &png, &png_length, "png", error, NULL)) {
        g_object_unref(source);
        return NULL;
    }
    g_object_unref(source);
    GInputStream *stream = g_memory_input_stream_new_from_data(png, png_length, g_free);
    GdkPixbuf *decoded = gdk_pixbuf_new_from_stream(stream, NULL, error);
    g_object_unref(stream);
    return decoded;
}

static void close_window(GtkWidget *widget, gpointer data)
{
    Welcome *app = data;
    (void)widget;
    app->window = NULL;
    if (gtk_main_level() > 0)
        gtk_main_quit();
}

static gboolean count_draw(GtkWidget *widget, cairo_t *context, gpointer data)
{
    Welcome *app = data;
    (void)context;
    ++app->draw_count;
    if (!app->self_test && !app->mapped_reported && gtk_widget_get_mapped(widget)) {
        app->mapped_reported = TRUE;
        puts("GTK_WINDOW_MAPPED");
        fflush(stdout);
    }
    return FALSE;
}

static gboolean self_test_failed(Welcome *app, const char *operation)
{
    fprintf(stderr, "GTK_RUNTIME_FAILED: %s\n", operation);
    gtk_label_set_text(GTK_LABEL(app->status), "Проверка графического приложения не прошла.");
    app->exit_status = 1;
    gtk_main_quit();
    return G_SOURCE_REMOVE;
}

static gboolean test_window(gpointer data)
{
    Welcome *app = data;
    static const char test_text[] = "Проверка NekoOS: заметка в UTF-8.\nВторая строка: кот и окна.\n";
    if (!gtk_widget_get_realized(app->window) ||
        !gtk_widget_get_mapped(app->window) || app->draw_count == 0) {
        if (++app->readiness_retries < 25)
            return G_SOURCE_CONTINUE;
        return self_test_failed(app, "window was not realized, mapped and drawn");
    }
    if (!gtk_widget_get_realized(app->text_view) ||
        gtk_widget_get_allocated_width(app->text_view) <= 0 ||
        gtk_widget_get_allocated_height(app->text_view) <= 0)
        return self_test_failed(app, "text editor widget has no realized allocation");

    PangoLayout *layout = gtk_label_get_layout(GTK_LABEL(app->heading));
    int width = 0, height = 0;
    pango_layout_get_pixel_size(layout, &width, &height);
    if (width <= 0 || height <= 0 || pango_layout_get_unknown_glyphs_count(layout) != 0)
        return self_test_failed(app, "Cyrillic font layout has missing glyphs");
    if (gtk_image_get_storage_type(GTK_IMAGE(app->image)) != GTK_IMAGE_PIXBUF)
        return self_test_failed(app, "PNG image widget has no pixel buffer");
    GdkPixbuf *image = gtk_image_get_pixbuf(GTK_IMAGE(app->image));
    if (!image || gdk_pixbuf_get_width(image) != 48 ||
        gdk_pixbuf_get_height(image) != 48)
        return self_test_failed(app, "decoded PNG image has incorrect dimensions");

    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(app->text_view));
    gtk_text_buffer_set_text(buffer, test_text, -1);
    gtk_button_clicked(GTK_BUTTON(app->save_button));
    if (!app->save_ok || gtk_text_buffer_get_modified(buffer) ||
        !g_str_has_prefix(gtk_label_get_text(GTK_LABEL(app->status)), "Сохранено."))
        return self_test_failed(app, "Save button did not save the explicit test note");
    /* An existing regular test file cannot also be a parent directory. */
    gchar *saved_path = app->note_path;
    app->note_path = g_build_filename(saved_path, "cannot-save.txt", NULL);
    gtk_button_clicked(GTK_BUTTON(app->save_button));
    gboolean error_visible = !app->save_ok &&
        g_str_has_prefix(gtk_label_get_text(GTK_LABEL(app->status)), "Не удалось");
    g_free(app->note_path);
    app->note_path = saved_path;
    if (!error_visible)
        return self_test_failed(app, "Save failure did not produce a visible error");
    gtk_text_buffer_set_text(buffer, "", -1);
    if (!load_note(app))
        return self_test_failed(app, "test note could not be reloaded through GIO");
    GtkTextIter start, end;
    gtk_text_buffer_get_bounds(buffer, &start, &end);
    gchar *reloaded = gtk_text_buffer_get_text(buffer, &start, &end, FALSE);
    gboolean matches = strcmp(reloaded, test_text) == 0;
    g_free(reloaded);
    if (!matches || gtk_text_buffer_get_modified(buffer))
        return self_test_failed(app, "reloaded note differs from saved UTF-8 text");

    puts("GTK_RUNTIME_READY: realized GTK window, Cyrillic font, PNG image, Save and reload");
    fflush(stdout);
    app->exit_status = 0;
    gtk_main_quit();
    return G_SOURCE_REMOVE;
}

int main(int argc, char **argv)
{
    Welcome app = {0};
    if (argc == 3 && strcmp(argv[1], "--self-test") == 0) {
        if (!g_path_is_absolute(argv[2])) {
            fputs("Usage: neko-gtk-welcome --self-test ABSOLUTE_TEST_NOTE_PATH\n", stderr);
            return 2;
        }
        app.self_test = TRUE;
        app.exit_status = 1;
        app.note_path = g_strdup(argv[2]);
    } else if (argc != 1) {
        fputs("Usage: neko-gtk-welcome [--self-test ABSOLUTE_TEST_NOTE_PATH]\n", stderr);
        return 2;
    } else {
        app.note_path = g_build_filename(g_get_home_dir(), "Documents", "Neko-note.txt", NULL);
    }
    int gtk_argc = 1;
    char **gtk_argv = argv;
    gtk_init(&gtk_argc, &gtk_argv);
    g_set_application_name("NekoOS");

    app.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(app.window), "NekoOS");
    gtk_window_set_default_size(GTK_WINDOW(app.window), 680, 540);
    gtk_window_set_position(GTK_WINDOW(app.window), GTK_WIN_POS_CENTER);
    gtk_container_set_border_width(GTK_CONTAINER(app.window), 24);
    g_signal_connect(app.window, "delete-event", G_CALLBACK(confirm_close), &app);
    g_signal_connect(app.window, "destroy", G_CALLBACK(close_window), &app);
    g_signal_connect(app.window, "draw", G_CALLBACK(count_draw), &app);

    GtkWidget *content = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
    gtk_container_add(GTK_CONTAINER(app.window), content);
    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk_box_pack_start(GTK_BOX(content), header, FALSE, FALSE, 0);
    GError *image_error = NULL;
    GdkPixbuf *image = make_document_image(&image_error);
    app.image = gtk_image_new_from_pixbuf(image);
    if (image)
        g_object_unref(image);
    gtk_box_pack_start(GTK_BOX(header), app.image, FALSE, FALSE, 0);
    app.heading = gtk_label_new(NULL);
    gtk_label_set_markup(GTK_LABEL(app.heading),
                         "<span size='x-large' weight='bold'>Добро пожаловать в NekoOS</span>");
    gtk_label_set_xalign(GTK_LABEL(app.heading), 0.0f);
    gtk_label_set_line_wrap(GTK_LABEL(app.heading), TRUE);
    gtk_box_pack_start(GTK_BOX(header), app.heading, TRUE, TRUE, 0);

    GtkWidget *description = gtk_label_new(
        "Ваша заметка сохраняется в домашней папке и остаётся после выключения NekoOS.\n\n"
        "Напишите текст ниже и нажмите «Сохранить».");
    gtk_label_set_xalign(GTK_LABEL(description), 0.0f);
    gtk_label_set_line_wrap(GTK_LABEL(description), TRUE);
    gtk_box_pack_start(GTK_BOX(content), description, FALSE, FALSE, 0);

    GtkWidget *note_title = gtk_label_new("Моя заметка");
    gtk_label_set_xalign(GTK_LABEL(note_title), 0.0f);
    gtk_box_pack_start(GTK_BOX(content), note_title, FALSE, FALSE, 0);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll), GTK_POLICY_AUTOMATIC,
                                   GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_shadow_type(GTK_SCROLLED_WINDOW(scroll), GTK_SHADOW_IN);
    app.text_view = gtk_text_view_new();
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(app.text_view), GTK_WRAP_WORD_CHAR);
    gtk_text_view_set_left_margin(GTK_TEXT_VIEW(app.text_view), 12);
    gtk_text_view_set_right_margin(GTK_TEXT_VIEW(app.text_view), 12);
    gtk_text_view_set_top_margin(GTK_TEXT_VIEW(app.text_view), 10);
    gtk_text_view_set_bottom_margin(GTK_TEXT_VIEW(app.text_view), 10);
    gtk_container_add(GTK_CONTAINER(scroll), app.text_view);
    gtk_box_pack_start(GTK_BOX(content), scroll, TRUE, TRUE, 0);

    gchar *display_path = g_filename_display_name(app.note_path);
    GtkWidget *path_label = gtk_label_new(display_path);
    g_free(display_path);
    gtk_label_set_xalign(GTK_LABEL(path_label), 0.0f);
    gtk_label_set_selectable(GTK_LABEL(path_label), TRUE);
    gtk_label_set_ellipsize(GTK_LABEL(path_label), PANGO_ELLIPSIZE_MIDDLE);
    gtk_box_pack_start(GTK_BOX(content), path_label, FALSE, FALSE, 0);
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
    gtk_box_pack_start(GTK_BOX(content), actions, FALSE, FALSE, 0);
    app.status = gtk_label_new("");
    gtk_label_set_xalign(GTK_LABEL(app.status), 0.0f);
    gtk_label_set_line_wrap(GTK_LABEL(app.status), TRUE);
    gtk_label_set_max_width_chars(GTK_LABEL(app.status), 58);
    gtk_box_pack_start(GTK_BOX(actions), app.status, TRUE, TRUE, 0);
    app.save_button = gtk_button_new_with_label("Сохранить");
    g_signal_connect(app.save_button, "clicked", G_CALLBACK(save_note), &app);
    gtk_box_pack_start(GTK_BOX(actions), app.save_button, FALSE, FALSE, 0);
    GtkWidget *close_button = gtk_button_new_with_label("Закрыть");
    g_signal_connect(close_button, "clicked", G_CALLBACK(request_close), &app);
    gtk_box_pack_start(GTK_BOX(actions), close_button, FALSE, FALSE, 0);

    load_note(&app);
    if (image_error)
        show_error(&app, "Не удалось загрузить изображение", image_error);
    gtk_widget_show_all(app.window);
    gtk_widget_grab_focus(app.text_view);
    if (app.self_test)
        g_timeout_add(200, test_window, &app);
    gtk_main();
    if (app.window)
        gtk_widget_destroy(app.window);
    g_free(app.note_path);
    return app.exit_status;
}
