#define _GNU_SOURCE

#include "../rootfs/usr/bin/neko-files.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "test_neko_files:%d: %s failed\n", __LINE__, #condition); \
        exit(1); \
    } \
} while (0)

static size_t find_entry(const NekoFiles *files, const char *name)
{
    for (size_t i = 0; i < files->entry_count; i++)
        if (strcmp(files->entries[i].name, name) == 0) return i;
    fprintf(stderr, "missing entry: %s\n", name);
    exit(1);
}

static void put_file(int dir_fd, const char *name, const char *body)
{
    int fd = openat(dir_fd, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    CHECK(fd >= 0);
    size_t length = strlen(body);
    CHECK(write(fd, body, length) == (ssize_t)length);
    CHECK(close(fd) == 0);
}

int main(void)
{
    char template[] = "/tmp/neko-files-XXXXXX";
    char *home = mkdtemp(template);
    CHECK(home != NULL);
    int home_fd = open(home, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    CHECK(home_fd >= 0);
    CHECK(mkdirat(home_fd, "folder", 0700) == 0);
    CHECK(mkdirat(home_fd, "switch", 0700) == 0);
    put_file(home_fd, "zeta.txt", "last");
    put_file(home_fd, "Alpha.txt", "hello\nworld\t!\033[31m");
    put_file(home_fd, "binary.dat", "one\0two");
    int binary_fd = openat(home_fd, "binary.dat", O_WRONLY | O_APPEND);
    CHECK(binary_fd >= 0);
    CHECK(write(binary_fd, "\0two", 4) == 4);
    CHECK(close(binary_fd) == 0);
    put_file(home_fd, "escape\nname", "control name");
    CHECK(symlinkat("/etc", home_fd, "outside") == 0);
    CHECK(symlinkat("/etc/passwd", home_fd, "link.txt") == 0);

    NekoFiles files;
    CHECK(neko_files_init(&files, home) == 0);
    CHECK(strcmp(files.relative_path, "/") == 0);
    CHECK(files.entry_count == 8);
    CHECK(strcmp(files.entries[0].name, "folder") == 0);
    CHECK(strcmp(files.entries[1].name, "switch") == 0);
    CHECK(find_entry(&files, "Alpha.txt") < find_entry(&files, "zeta.txt"));
    CHECK(strcmp(files.entries[find_entry(&files, "escape\nname")].display_name,
                 "escape?name") == 0);
    CHECK(files.entries[find_entry(&files, "outside")].kind == NEKO_FILES_OTHER);
    CHECK(neko_files_enter(&files, find_entry(&files, "outside")) == -ENOTDIR);
    CHECK(neko_files_preview(&files, find_entry(&files, "link.txt"),
                             (char[16]){0}, 16, NULL) == -EINVAL);
    CHECK(neko_files_rename(&files, find_entry(&files, "link.txt"),
                            "moved-link") == -EINVAL);

    char preview[64];
    int truncated = 0;
    CHECK(neko_files_preview(&files, find_entry(&files, "Alpha.txt"),
                             preview, sizeof preview, &truncated) == 0);
    CHECK(strcmp(preview, "hello\nworld !?[31m") == 0);
    CHECK(truncated == 0);
    CHECK(neko_files_preview(&files, find_entry(&files, "binary.dat"),
                             preview, sizeof preview, &truncated) == -EILSEQ);
    CHECK(neko_files_preview(&files, find_entry(&files, "Alpha.txt"),
                             preview, 8, &truncated) == 0);
    CHECK(strlen(preview) <= 7 && truncated == 1);

    /* A listed directory cannot become an escape route by switching to a link. */
    size_t switch_index = find_entry(&files, "switch");
    CHECK(unlinkat(home_fd, "switch", AT_REMOVEDIR) == 0);
    CHECK(symlinkat("/etc", home_fd, "switch") == 0);
    CHECK(neko_files_enter(&files, switch_index) < 0);
    CHECK(strcmp(files.relative_path, "/") == 0);
    CHECK(unlinkat(home_fd, "switch", 0) == 0);
    CHECK(neko_files_refresh(&files) == 0);

    CHECK(neko_files_enter(&files, find_entry(&files, "folder")) == 0);
    CHECK(strcmp(files.relative_path, "/folder") == 0);
    CHECK(neko_files_up(&files) == 0);
    CHECK(strcmp(files.relative_path, "/") == 0);
    CHECK(neko_files_up(&files) == 0);
    CHECK(strcmp(files.relative_path, "/") == 0);
    CHECK(neko_files_enter(&files, find_entry(&files, "folder")) == 0);

    CHECK(neko_files_create_file(&files, "new.txt") == 0);
    CHECK(neko_files_create_file(&files, "new.txt") == -EEXIST);
    CHECK(neko_files_create_file(&files, "../escape") == -EINVAL);
    CHECK(neko_files_create_file(&files, "control\nname") == -EINVAL);
    CHECK(neko_files_create_file(&files, "\xc0\x80") == -EINVAL);
    CHECK(neko_files_create_file(&files, "caf\xc3\xa9.txt") == 0);
    CHECK(neko_files_create_dir(&files, "notes") == 0);
    CHECK(neko_files_create_dir(&files, "notes") == -EEXIST);
    CHECK(neko_files_create_dir(&files, "../escape") == -EINVAL);
    CHECK(files.entries[find_entry(&files, "notes")].kind == NEKO_FILES_DIRECTORY);
    CHECK(neko_files_rename(&files, find_entry(&files, "new.txt"),
                            "renamed.txt") == 0);
    CHECK(neko_files_rename(&files, find_entry(&files, "renamed.txt"),
                            "caf\xc3\xa9.txt") == -EEXIST);
    CHECK(files.entry_count == 3);
    neko_files_close(&files);

    /* These operations must be visible in a fresh session, not just the cache. */
    CHECK(neko_files_init(&files, home) == 0);
    CHECK(neko_files_enter(&files, find_entry(&files, "folder")) == 0);
    CHECK(files.entry_count == 3);
    CHECK(find_entry(&files, "renamed.txt") < files.entry_count);
    CHECK(find_entry(&files, "caf\xc3\xa9.txt") < files.entry_count);
    CHECK(files.entries[find_entry(&files, "notes")].kind == NEKO_FILES_DIRECTORY);

    int folder_fd = openat(home_fd, "folder", O_RDONLY | O_DIRECTORY);
    CHECK(folder_fd >= 0);
    for (int i = 0; i < 140; i++) {
        char name[32];
        snprintf(name, sizeof name, "many-%03d", i);
        put_file(folder_fd, name, "x");
    }
    CHECK(neko_files_refresh(&files) == 0);
    CHECK(files.entry_count == NEKO_FILES_MAX_ENTRIES);
    CHECK(files.truncated == 1);
    neko_files_close(&files);

    for (int i = 0; i < 140; i++) {
        char name[32];
        snprintf(name, sizeof name, "many-%03d", i);
        CHECK(unlinkat(folder_fd, name, 0) == 0);
    }
    CHECK(unlinkat(folder_fd, "renamed.txt", 0) == 0);
    CHECK(unlinkat(folder_fd, "caf\xc3\xa9.txt", 0) == 0);
    CHECK(unlinkat(folder_fd, "notes", AT_REMOVEDIR) == 0);
    CHECK(close(folder_fd) == 0);
    CHECK(unlinkat(home_fd, "folder", AT_REMOVEDIR) == 0);
    for (size_t i = 0; i < 6; i++) {
        const char *name[] = {"zeta.txt", "Alpha.txt", "binary.dat",
                              "escape\nname", "outside", "link.txt"};
        CHECK(unlinkat(home_fd, name[i], 0) == 0);
    }
    CHECK(close(home_fd) == 0);
    CHECK(rmdir(home) == 0);
    puts("neko files model: ok");
    return 0;
}
