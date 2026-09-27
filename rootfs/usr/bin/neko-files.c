#define _GNU_SOURCE

#include "neko-files.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define NEKO_FILES_SCAN_LIMIT 2048
#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE 1u
#endif

/* Decode one UTF-8 scalar, rejecting overlong sequences and surrogates. */
static size_t decode_utf8(const unsigned char *s, size_t left, uint32_t *cp)
{
    if (!left) return 0;
    unsigned char a = s[0];
    if (a < 0x80) { *cp = a; return 1; }
    size_t width;
    uint32_t value;
    if (a >= 0xc2 && a <= 0xdf) { width = 2; value = a & 0x1f; }
    else if (a >= 0xe0 && a <= 0xef) { width = 3; value = a & 0x0f; }
    else if (a >= 0xf0 && a <= 0xf4) { width = 4; value = a & 0x07; }
    else return 0;
    if (left < width) return 0;
    for (size_t i = 1; i < width; i++) {
        if ((s[i] & 0xc0) != 0x80) return 0;
        value = (value << 6) | (s[i] & 0x3f);
    }
    if ((width == 2 && value < 0x80) ||
        (width == 3 && value < 0x800) ||
        (width == 4 && value < 0x10000) ||
        (value >= 0xd800 && value <= 0xdfff) || value > 0x10ffff)
        return 0;
    *cp = value;
    return width;
}

static int unsafe_codepoint(uint32_t cp)
{
    return cp < 0x20 || (cp >= 0x7f && cp <= 0x9f) ||
           cp == 0x061c || cp == 0x200e || cp == 0x200f ||
           (cp >= 0x2028 && cp <= 0x202e) ||
           (cp >= 0x2066 && cp <= 0x2069);
}

static int valid_name(const char *name)
{
    if (!name) return 0;
    size_t length = strnlen(name, NEKO_FILES_MAX_NAME + 1);
    if (!length || length > NEKO_FILES_MAX_NAME ||
        (length == 1 && name[0] == '.') ||
        (length == 2 && name[0] == '.' && name[1] == '.'))
        return 0;
    const unsigned char *bytes = (const unsigned char *)name;
    for (size_t i = 0; i < length;) {
        uint32_t cp;
        size_t width = decode_utf8(bytes + i, length - i, &cp);
        if (!width || unsafe_codepoint(cp) || cp == '/' || cp == '\\')
            return 0;
        i += width;
    }
    return 1;
}

static void safe_display_name(char *out, const char *name)
{
    size_t length = strnlen(name, NEKO_FILES_MAX_NAME + 1);
    size_t used = 0;
    const unsigned char *bytes = (const unsigned char *)name;
    for (size_t i = 0; i < length && used < NEKO_FILES_MAX_NAME;) {
        uint32_t cp;
        size_t width = decode_utf8(bytes + i, length - i, &cp);
        if (!width || unsafe_codepoint(cp)) {
            out[used++] = '?';
            i += width ? width : 1;
        } else {
            if (used + width > NEKO_FILES_MAX_NAME) break;
            memcpy(out + used, bytes + i, width);
            used += width;
            i += width;
        }
    }
    out[used] = '\0';
}

static int ascii_fold(unsigned char ch)
{
    return ch >= 'A' && ch <= 'Z' ? ch + ('a' - 'A') : ch;
}

static int compare_entries(const NekoFileEntry *a, const NekoFileEntry *b)
{
    if (a->kind == NEKO_FILES_DIRECTORY && b->kind != NEKO_FILES_DIRECTORY)
        return -1;
    if (b->kind == NEKO_FILES_DIRECTORY && a->kind != NEKO_FILES_DIRECTORY)
        return 1;
    const unsigned char *left = (const unsigned char *)a->name;
    const unsigned char *right = (const unsigned char *)b->name;
    while (*left && *right) {
        int difference = ascii_fold(*left) - ascii_fold(*right);
        if (difference) return difference;
        left++;
        right++;
    }
    if (*left || *right) return *left ? 1 : -1;
    return strcmp(a->name, b->name);
}

static void insert_entry(NekoFiles *files, const NekoFileEntry *entry)
{
    size_t count = files->entry_count;
    if (count == NEKO_FILES_MAX_ENTRIES) {
        files->truncated = 1;
        if (compare_entries(entry, &files->entries[count - 1]) >= 0) return;
    } else {
        files->entry_count++;
    }
    size_t at = 0;
    while (at < count && compare_entries(entry, &files->entries[at]) >= 0)
        at++;
    size_t move = files->entry_count - at - 1;
    if (move)
        memmove(&files->entries[at + 1], &files->entries[at],
                move * sizeof files->entries[0]);
    files->entries[at] = *entry;
}

int neko_files_refresh(NekoFiles *files)
{
    if (!files || files->depth > NEKO_FILES_MAX_DEPTH ||
        files->dir_fds[files->depth] < 0)
        return -EBADF;
    files->entry_count = 0;
    files->truncated = 0;
    int scan_fd = openat(files->dir_fds[files->depth], ".",
                         O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (scan_fd < 0) return -errno;
    DIR *directory = fdopendir(scan_fd);
    if (!directory) { int error = errno; close(scan_fd); return -error; }
    size_t scanned = 0;
    int result = 0;
    for (;;) {
        errno = 0;
        struct dirent *item = readdir(directory);
        if (!item) { if (errno) result = -errno; break; }
        if (strcmp(item->d_name, ".") == 0 ||
            strcmp(item->d_name, "..") == 0)
            continue;
        if (scanned++ >= NEKO_FILES_SCAN_LIMIT) {
            files->truncated = 1;
            break;
        }
        size_t length = strnlen(item->d_name, NEKO_FILES_MAX_NAME + 1);
        if (!length || length > NEKO_FILES_MAX_NAME) {
            files->truncated = 1;
            continue;
        }
        struct stat metadata;
        if (fstatat(dirfd(directory), item->d_name, &metadata,
                    AT_SYMLINK_NOFOLLOW) < 0)
            continue; /* A concurrent rename can make an entry disappear. */
        NekoFileEntry entry;
        memset(&entry, 0, sizeof entry);
        memcpy(entry.name, item->d_name, length + 1);
        safe_display_name(entry.display_name, entry.name);
        entry.kind = S_ISDIR(metadata.st_mode) ? NEKO_FILES_DIRECTORY :
                     S_ISREG(metadata.st_mode) ? NEKO_FILES_REGULAR :
                     NEKO_FILES_OTHER;
        entry.size = metadata.st_size > 0 ? (uint64_t)metadata.st_size : 0;
        insert_entry(files, &entry);
    }
    if (closedir(directory) < 0 && result == 0) result = -errno;
    return result;
}

int neko_files_init(NekoFiles *files, const char *home_path)
{
    if (!files || !home_path || !*home_path) return -EINVAL;
    memset(files, 0, sizeof *files);
    for (size_t i = 0; i <= NEKO_FILES_MAX_DEPTH; i++)
        files->dir_fds[i] = -1;
    int fd = open(home_path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return -errno;
    files->dir_fds[0] = fd;
    files->relative_path[0] = '/';
    files->relative_path[1] = '\0';
    files->path_lengths[0] = 1;
    int result = neko_files_refresh(files);
    if (result < 0) neko_files_close(files);
    return result;
}

void neko_files_close(NekoFiles *files)
{
    if (!files) return;
    for (size_t i = 0; i <= NEKO_FILES_MAX_DEPTH; i++) {
        if (files->dir_fds[i] >= 0) close(files->dir_fds[i]);
        files->dir_fds[i] = -1;
    }
    files->depth = 0;
    files->entry_count = 0;
    files->truncated = 0;
    files->relative_path[0] = '\0';
}

int neko_files_enter(NekoFiles *files, size_t index)
{
    if (!files || index >= files->entry_count) return -EINVAL;
    if (files->entries[index].kind != NEKO_FILES_DIRECTORY) return -ENOTDIR;
    if (files->depth == NEKO_FILES_MAX_DEPTH) return -ENAMETOOLONG;
    const char *name = files->entries[index].name;
    const char *display = files->entries[index].display_name;
    size_t old_length = files->path_lengths[files->depth];
    size_t name_length = strlen(display);
    size_t separator = files->depth ? 1 : 0;
    if (old_length + separator + name_length >= NEKO_FILES_MAX_PATH)
        return -ENAMETOOLONG;
    int fd = openat(files->dir_fds[files->depth], name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return -errno;
    if (separator) files->relative_path[old_length++] = '/';
    memcpy(files->relative_path + old_length, display, name_length + 1);
    files->depth++;
    files->dir_fds[files->depth] = fd;
    files->path_lengths[files->depth] = old_length + name_length;
    return neko_files_refresh(files);
}

int neko_files_up(NekoFiles *files)
{
    if (!files || files->dir_fds[0] < 0) return -EBADF;
    if (files->depth == 0) return 0;
    close(files->dir_fds[files->depth]);
    files->dir_fds[files->depth] = -1;
    files->depth--;
    files->relative_path[files->path_lengths[files->depth]] = '\0';
    return neko_files_refresh(files);
}

int neko_files_preview(NekoFiles *files, size_t index, char *out,
                       size_t capacity, int *truncated)
{
    if (!files || index >= files->entry_count || !out || capacity < 2)
        return -EINVAL;
    out[0] = '\0';
    if (truncated) *truncated = 0;
    if (files->entries[index].kind != NEKO_FILES_REGULAR) return -EINVAL;
    int fd = openat(files->dir_fds[files->depth], files->entries[index].name,
                    O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return -errno;
    struct stat metadata;
    if (fstat(fd, &metadata) < 0) {
        int error = errno;
        close(fd);
        return -error;
    }
    if (!S_ISREG(metadata.st_mode)) { close(fd); return -EINVAL; }
    unsigned char raw[NEKO_FILES_MAX_PREVIEW];
    size_t limit = capacity - 1 < sizeof raw ? capacity - 1 : sizeof raw;
    size_t got = 0;
    while (got < limit && got < sizeof raw) {
        size_t count = sizeof raw - got;
        if (count > limit - got) count = limit - got;
        ssize_t amount = read(fd, raw + got, count);
        if (amount > 0) { got += (size_t)amount; continue; }
        if (amount == 0) break;
        if (errno == EINTR) continue;
        int error = errno;
        close(fd);
        return -error;
    }
    close(fd);
    if (truncated && metadata.st_size > (off_t)got) *truncated = 1;
    for (size_t i = 0; i < got; i++)
        if (raw[i] == 0) return -EILSEQ; /* Do not present binary as text. */
    size_t used = 0;
    for (size_t i = 0; i < got;) {
        uint32_t cp;
        size_t width = decode_utf8(raw + i, got - i, &cp);
        if (raw[i] == '\n' || raw[i] == '\t') {
            out[used++] = raw[i] == '\n' ? '\n' : ' ';
            i++;
        } else if (!width || unsafe_codepoint(cp)) {
            out[used++] = '?';
            i += width ? width : 1;
        } else {
            memcpy(out + used, raw + i, width);
            used += width;
            i += width;
        }
    }
    out[used] = '\0';
    return 0;
}

int neko_files_create_file(NekoFiles *files, const char *name)
{
    if (!files || files->dir_fds[0] < 0) return -EBADF;
    if (!valid_name(name)) return -EINVAL;
    int fd = openat(files->dir_fds[files->depth], name,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    0644);
    if (fd < 0) return -errno;
    if (close(fd) < 0) return -errno;
    return neko_files_refresh(files);
}

int neko_files_create_dir(NekoFiles *files, const char *name)
{
    if (!files || files->dir_fds[0] < 0) return -EBADF;
    if (!valid_name(name)) return -EINVAL;
    if (mkdirat(files->dir_fds[files->depth], name, 0755) < 0)
        return -errno;
    return neko_files_refresh(files);
}

int neko_files_rename(NekoFiles *files, size_t index, const char *new_name)
{
    if (!files || index >= files->entry_count) return -EINVAL;
    if (!valid_name(new_name)) return -EINVAL;
    if (files->entries[index].kind != NEKO_FILES_REGULAR) return -EINVAL;
    const char *old_name = files->entries[index].name;
    if (strcmp(old_name, new_name) == 0) return 0;
    struct stat metadata;
    if (fstatat(files->dir_fds[files->depth], old_name, &metadata,
                AT_SYMLINK_NOFOLLOW) < 0)
        return -errno;
    if (!S_ISREG(metadata.st_mode)) return -EINVAL;
#if defined(__linux__) && defined(SYS_renameat2)
    int fd = files->dir_fds[files->depth];
    if (syscall(SYS_renameat2, fd, old_name, fd, new_name,
                RENAME_NOREPLACE) < 0)
        return -errno;
    return neko_files_refresh(files);
#else
    return -ENOSYS;
#endif
}
