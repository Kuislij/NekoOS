# Kernel

`configs/x86_64.config` задаёт минимальные встроенные возможности для QEMU:
serial console, два CPU (SMP), локальный APIC и прерывания, initramfs,
ELF/scripts, proc/sys/devtmpfs/tmpfs, ACPI, virtio-blk и ext4.
Фрагмент применяется через KCONFIG_ALLCONFIG + allnoconfig; полный результат
сохраняется в `out/images/kernel.config`. Модули и сеть пока выключены.
Версия, URL и SHA256 находятся в `configs/sources.sh`.
