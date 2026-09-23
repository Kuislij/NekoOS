# Архитектура

Windows — хост; WSL2 — среда разработки; QEMU — тестовая машина.
NekoOS использует upstream Linux, собственные настройки сборки и initramfs.

## Текущий цикл

`configs/sources.sh` → HTTPS download/cache → SHA256 → подпись Linux →
извлечение → Linux/BusyBox build → rootfs staging → cpio.gz → QEMU → serial log.

Bash управляет короткими этапами, Make собирает upstream-компоненты,
Python 3 используется только на хосте для автоматизации теста. В госте
Python нет. Ninja пока нужен только для проверки будущего host toolchain.

В госте `/init` монтирует proc/sys/devtmpfs/devpts/tmpfs, затем передаёт PID 1
BusyBox init. `inittab` запускает ash на ttyS0 и восстанавливает shell после
выхода. Init также обрабатывает завершение процессов и штатное выключение.

BusyBox статически связан с host glibc. Это bootstrap-компромисс, а не
окончательный выбор libc. Загрузчик пока не требуется: QEMU принимает ядро
и initramfs напрямую. Диск, installer, ISO и постоянное хранилище отсутствуют.

## Каталоги

| Путь | Назначение |
| --- | --- |
| `configs/` | Закреплённые источники и выбор applets BusyBox |
| `kernel/configs/` | Конфигурация x86_64 Linux |
| `rootfs/` | Исходные `/init` и `/etc`, README не включается в образ |
| `scripts/`, `tools/` | Сборка, запуск, проверки |
| `keys/` | Закреплённый публичный ключ подписи Linux |
| `docs/adr/` | Архитектурные решения |
| `packages/` | Место для будущих собственных recipes |
| `cache/sources/` | Upstream-архивы и подпись |
| `build/sources/` | Извлечённые исходники |
| `build/linux-*`, `build/busybox-*` | Результаты компиляции |
| `build/rootfs/` | Генерируемое дерево; пересоздаётся при сборке |
| `build/logs/` | Сборочные и serial logs |
| `out/images/` | Ядро, initramfs, конфигурации и hashes |

Будущие `cache/packages/` и `out/repository/` отделены концептуально, но пока
не нужны. Генерируемые деревья не попадают в Git.

## Отложенные решения

Язык package manager: Rust даёт memory safety ценой bootstrap toolchain;
Go упрощает разработку, но требует отдельного toolchain; C/C++ требуют
ручного контроля памяти; Python добавляет runtime в guest. Выбор будет
сделан перед MVP. Формат пакетов, libc, постоянный rootfs и система сервисов
пока не зафиксированы. См. ADR-002 о границах минимальной загрузки.
