# Проверка загрузки системного диска через BIOS ISO — 2026-09-26

Среда: WSL2 Ubuntu, QEMU x86_64 TCG, виртуальный BIOS и GRUB. Сборка создала
ядро, полный и маленький initramfs; `bash os iso --system` создал отдельный
`NekoOS-system.iso` с пунктом системного диска по умолчанию.

`bash os test --iso --system --no-build` дважды прошёл путь BIOS → GRUB →
ядро → bootstrap → `switch_root` → BusyBox init → консоль на **двух временных
ext4-дисках**. Лог содержит `NEKO_BOOTLOADER_SYSTEM_READY`,
`SYSTEM_DISK_READY`, `PERSISTENCE_READY`, `SYSTEM_READY`, `HARDWARE_READY`.
Проверены два CPU, ACPI, системный корень `/dev/vda`, диск данных `/dev/vdb`,
DHCP, сохранение файлов в `/etc` и `/root`, компиляция C-программы и штатное
выключение. Результат: `ISO_SYSTEM_TEST_PASSED`.

Исходный `bash os iso` по-прежнему создал `NekoOS.iso` с прежним пунктом по
умолчанию; `bash os test --iso --no-build` прошёл две загрузки и сохранение
данных: `ISO_BOOT_TEST_PASSED`. Также прошли `SYSTEM_TEST_PASSED` для прямой
загрузки системного диска и `BOOT_TEST_PASSED` для временной консоли.

Настоящий `bash os run --iso --system` загрузился с уже существующих
`out/disks/system.img` и `state.img`. GRUB выделил системный пункт; гостевая
команда `mount` показала `/dev/vda on / type ext4 (rw,noatime)`. VM штатно
выключилась. Диски не форматировались и не заменялись.

Проверка ограничена виртуальным BIOS QEMU. ISO не является установщиком;
UEFI, физические диски и Windows Boot Manager не изменялись.
