#include "../rootfs/usr/bin/neko-system.h"

#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>

int main(void)
{
    errno = 0;
    assert(neko_system_read(NULL) == -1);
    assert(errno == EINVAL);

    NekoSystemInfo info;
    assert(neko_system_read(&info) == 0);
    assert(info.valid != 0);
    if (info.valid & NEKO_SYSTEM_KERNEL_RELEASE)
        assert(info.kernel_release[0] != '\0');
    if (info.valid & NEKO_SYSTEM_MEMORY_TOTAL)
        assert(info.memory_total_bytes > 0);
    if ((info.valid & (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE)) ==
        (NEKO_SYSTEM_MEMORY_TOTAL | NEKO_SYSTEM_MEMORY_FREE))
        assert(info.memory_available_bytes <= info.memory_total_bytes);
    if (info.valid & NEKO_SYSTEM_DISK_TOTAL)
        assert(info.disk_total_bytes > 0);
    if ((info.valid & (NEKO_SYSTEM_DISK_TOTAL | NEKO_SYSTEM_DISK_FREE)) ==
        (NEKO_SYSTEM_DISK_TOTAL | NEKO_SYSTEM_DISK_FREE))
        assert(info.disk_available_bytes <= info.disk_total_bytes);
    if (info.valid & NEKO_SYSTEM_CPU_COUNT)
        assert(info.cpu_count > 0);

    puts("NEKO_SYSTEM_MODEL_OK");
    return 0;
}
