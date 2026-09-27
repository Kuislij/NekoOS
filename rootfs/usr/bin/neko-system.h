#ifndef NEKO_SYSTEM_H
#define NEKO_SYSTEM_H

#include <stdint.h>

#define NEKO_SYSTEM_KERNEL_RELEASE (1u << 0)
#define NEKO_SYSTEM_UPTIME         (1u << 1)
#define NEKO_SYSTEM_MEMORY_TOTAL   (1u << 2)
#define NEKO_SYSTEM_MEMORY_FREE    (1u << 3)
#define NEKO_SYSTEM_DISK_TOTAL     (1u << 4)
#define NEKO_SYSTEM_DISK_FREE      (1u << 5)
#define NEKO_SYSTEM_CPU_COUNT      (1u << 6)

typedef struct {
    /* Check valid before displaying a field. All unavailable values are zero. */
    unsigned int valid;
    char kernel_release[128];
    uint64_t uptime_seconds;
    uint64_t memory_total_bytes;
    uint64_t memory_available_bytes;
    uint64_t disk_total_bytes;
    uint64_t disk_available_bytes; /* Free space available to this user. */
    unsigned int cpu_count;
} NekoSystemInfo;

/* Returns 0 if any field was read, or -1 with errno on invalid arguments or
 * when every source failed. Missing individual fields have their valid bit
 * cleared; callers can still display the other values. */
int neko_system_read(NekoSystemInfo *out);

#endif
