#define _POSIX_C_SOURCE 200809L

#include "neko-system.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <unistd.h>

static int read_uptime(uint64_t *seconds)
{
    char line[128];
    int fd = open("/proc/uptime", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t count;
    do {
        count = read(fd, line, sizeof line - 1);
    } while (count < 0 && errno == EINTR);
    close(fd);
    if (count <= 0 || line[0] < '0' || line[0] > '9') return -1;
    line[count] = '\0';

    /* /proc/uptime starts with an integer number of seconds followed by a
     * fractional part; parsing the integer avoids floating-point rounding. */
    char *end;
    errno = 0;
    unsigned long long value = strtoull(line, &end, 10);
    if (errno != 0 || end == line || (*end != '.' && !isspace((unsigned char)*end)))
        return -1;
    *seconds = (uint64_t)value;
    return 0;
}

static int parse_mem_kib(const char *line, const char *key, uint64_t *bytes)
{
    size_t key_length = strlen(key);
    if (strncmp(line, key, key_length) != 0 || line[key_length] != ':') return 0;
    const char *cursor = line + key_length + 1;
    while (isspace((unsigned char)*cursor)) cursor++;
    if (*cursor < '0' || *cursor > '9') return -1;

    char *end;
    errno = 0;
    unsigned long long kib = strtoull(cursor, &end, 10);
    if (errno != 0 || end == cursor || kib > UINT64_MAX / 1024u) return -1;
    while (isspace((unsigned char)*end)) end++;
    if (end[0] != 'k' || end[1] != 'B') return -1;
    end += 2;
    while (isspace((unsigned char)*end)) end++;
    if (*end != '\0') return -1;
    *bytes = (uint64_t)kib * 1024u;
    return 1;
}

static unsigned int add_memory_line(NekoSystemInfo *out, const char *line)
{
    unsigned int found = 0;
    uint64_t bytes;
    int status = parse_mem_kib(line, "MemTotal", &bytes);
    if (status == 1) {
        out->memory_total_bytes = bytes;
        found |= NEKO_SYSTEM_MEMORY_TOTAL;
    }
    status = parse_mem_kib(line, "MemAvailable", &bytes);
    if (status == 1) {
        out->memory_available_bytes = bytes;
        found |= NEKO_SYSTEM_MEMORY_FREE;
    }
    return found;
}

static unsigned int read_memory(NekoSystemInfo *out)
{
    int fd = open("/proc/meminfo", O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;

    char buffer[512];
    char line[256];
    size_t length = 0;
    int discard = 0;
    unsigned int found = 0;
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof buffer);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        for (ssize_t i = 0; i < count; i++) {
            if (buffer[i] == '\n') {
                if (!discard) {
                    line[length] = '\0';
                    found |= add_memory_line(out, line);
                }
                length = 0;
                discard = 0;
                if ((found & (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE)) ==
                    (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE)) goto done;
            } else if (!discard) {
                if (length + 1 < sizeof line) line[length++] = buffer[i];
                else discard = 1;
            }
        }
    }
    if (!discard && length != 0) {
        line[length] = '\0';
        found |= add_memory_line(out, line);
    }
done:
    close(fd);
    return found;
}

static int multiply_blocks(uint64_t blocks, uint64_t block_size, uint64_t *bytes)
{
    if (block_size == 0 || blocks > UINT64_MAX / block_size) return -1;
    *bytes = blocks * block_size;
    return 0;
}

int neko_system_read(NekoSystemInfo *out)
{
    if (out == NULL) {
        errno = EINVAL;
        return -1;
    }
    memset(out, 0, sizeof *out);

    struct utsname kernel;
    if (uname(&kernel) == 0 && kernel.release[0] != '\0') {
        size_t length = strnlen(kernel.release, sizeof kernel.release);
        if (length >= sizeof out->kernel_release)
            length = sizeof out->kernel_release - 1;
        memcpy(out->kernel_release, kernel.release, length);
        out->kernel_release[length] = '\0';
        out->valid |= NEKO_SYSTEM_KERNEL_RELEASE;
    }

    if (read_uptime(&out->uptime_seconds) == 0) out->valid |= NEKO_SYSTEM_UPTIME;
    out->valid |= read_memory(out);

    struct statvfs filesystem;
    if (statvfs("/", &filesystem) == 0) {
        uint64_t block_size = filesystem.f_frsize != 0 ?
                              filesystem.f_frsize : filesystem.f_bsize;
        if (multiply_blocks(filesystem.f_blocks, block_size,
                            &out->disk_total_bytes) == 0)
            out->valid |= NEKO_SYSTEM_DISK_TOTAL;
        if (multiply_blocks(filesystem.f_bavail, block_size,
                            &out->disk_available_bytes) == 0)
            out->valid |= NEKO_SYSTEM_DISK_FREE;
    }

    long online = sysconf(_SC_NPROCESSORS_ONLN);
    if (online > 0 && (unsigned long)online <= UINT_MAX) {
        out->cpu_count = (unsigned int)online;
        out->valid |= NEKO_SYSTEM_CPU_COUNT;
    }

    if (out->valid != 0) return 0;
    errno = EIO;
    return -1;
}
