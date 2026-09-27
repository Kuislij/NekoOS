/* Bounded, read-only browsing plus explicit file creation/rename for NekoOS. */
#ifndef NEKO_FILES_H
#define NEKO_FILES_H

#include <stddef.h>
#include <stdint.h>

#define NEKO_FILES_MAX_ENTRIES 128
#define NEKO_FILES_MAX_NAME 255
#define NEKO_FILES_MAX_PATH 1024
#define NEKO_FILES_MAX_DEPTH 16
#define NEKO_FILES_MAX_PREVIEW 4096

typedef enum {
    NEKO_FILES_DIRECTORY,
    NEKO_FILES_REGULAR,
    NEKO_FILES_OTHER
} NekoFileKind;

typedef struct {
    char name[NEKO_FILES_MAX_NAME + 1]; /* Exact name for indexed operations. */
    char display_name[NEKO_FILES_MAX_NAME + 1]; /* Safe UTF-8 for display. */
    NekoFileKind kind;
    uint64_t size;
} NekoFileEntry;

typedef struct {
    /* Initialize with neko_files_init() before use; close before reinitializing. */
    int dir_fds[NEKO_FILES_MAX_DEPTH + 1];
    size_t path_lengths[NEKO_FILES_MAX_DEPTH + 1];
    size_t depth;
    char relative_path[NEKO_FILES_MAX_PATH]; /* Safe display path; root is "/". */
    NekoFileEntry entries[NEKO_FILES_MAX_ENTRIES];
    size_t entry_count;
    int truncated; /* More than MAX_ENTRIES, or the scan limit was reached. */
} NekoFiles;

/* All functions return 0 or a negative errno value. home_path is a trusted
 * directory (normally "/home/neko"); navigation cannot leave its opened fd.
 * Entries are sorted directories first, then case-insensitive by name.
 */
int neko_files_init(NekoFiles *files, const char *home_path);
void neko_files_close(NekoFiles *files);
int neko_files_refresh(NekoFiles *files);
int neko_files_enter(NekoFiles *files, size_t index);
int neko_files_up(NekoFiles *files); /* At root this is a successful no-op. */

/* Preview only regular files. The result is sanitized UTF-8 text, always NUL
 * terminated, with at most MIN(capacity - 1, MAX_PREVIEW) output bytes.
 */
int neko_files_preview(NekoFiles *files, size_t index, char *out,
                       size_t capacity, int *truncated);

/* Names must be single, printable UTF-8 components of at most 255 bytes.
 * Create is exclusive; rename never replaces an existing destination.
 * Rename accepts only a regular-file entry, never a directory or symlink.
 */
int neko_files_create_file(NekoFiles *files, const char *name);
int neko_files_create_dir(NekoFiles *files, const char *name);
int neko_files_rename(NekoFiles *files, size_t index, const char *new_name);

#endif
