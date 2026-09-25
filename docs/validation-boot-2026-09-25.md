# Проверка BIOS-загрузки — 2026-09-25

Среда: WSL2, Ubuntu 26.04.1, QEMU x86_64 TCG с машиной q35, виртуальным
BIOS, двумя CPU, 256 МиБ RAM и отдельным virtio-диском `state.img`.
Физические устройства Windows не подключались. Собраны Linux 6.12.111,
BusyBox 1.37.0, musl 1.2.6 и TinyCC 0.9.27.

1. `bash os build` завершился с `BUILD_READY`; конфигурация ядра содержит
   `CONFIG_SMP=y`, `CONFIG_NR_CPUS=2`, APIC, ACPI, virtio-blk и ext4.
2. `bash os iso` создал `out/images/NekoOS.iso`. `xorriso` подтвердил
   загрузочный каталог El Torito с платформой BIOS и GRUB.
3. `bash os test --iso --no-build --timeout 120` прошёл два полных цикла
   BIOS → GRUB → Linux → `/init` → BusyBox shell → poweroff. В serial log
   присутствуют `NEKO_BOOTLOADER_READY` и `HARDWARE_READY`.
4. Ядро сообщило о двух активированных процессорах, таблицах ACPI и маршрутизации
   прерываний через IOAPIC. Гостевая проверка увидела диапазон CPU `0-1`,
   `MemTotal`, карту RAM, локальный APIC и таблицу ACPI DSDT.
5. Ядро обнаружило virtio-blk `/dev/vda` на 512 МиБ. `/init` смонтировал ext4
   в `/state`. Тест создал файлы в `/root`, `/home`, `/var/lib`, выключил машину,
   загрузил её повторно, прочитал файлы и удалил тестовые данные:
   `ISO_BOOT_TEST_PASSED`.
6. Старые пути запуска после изменения ядра также прошли:
   `bash os test --no-build` → `BOOT_TEST_PASSED`, `bash os test --disk --no-build`
   → `DISK_TEST_PASSED`.
7. Пользовательская команда `bash os run --iso` также открыла консоль `neko#`.
   В ней `neko-boot-status` вывел `Online CPUs: 0-1`, таблицу ACPI DSDT,
   смонтированный ext4-диск и `HARDWARE_READY`; `poweroff` завершил QEMU.

Это проверка виртуального BIOS и устройств QEMU. Инициализацию CPU, RAM,
прерываний, ACPI и virtio выполняет ядро Linux; собственных драйверов для
физического оборудования здесь пока нет. ISO требует отдельный виртуальный
диск с данными и не является установщиком или UEFI-образом.
