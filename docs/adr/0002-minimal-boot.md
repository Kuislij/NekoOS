# ADR-002: минимальная загрузка Linux и BusyBox

Статус: принято для этапа 2. Дата: 2026-09-23.

## Сравнение

* Initramfs проще дискового rootfs: нет разделов, filesystem driver и bootloader.
  Цена — отсутствие сохранения данных и размещение всего дерева в RAM.
* BusyBox даёт shell, init и небольшие утилиты одним бинарником. GNU userspace
  потребует больше компонентов; Toybox не закрывает тот же bootstrap init.
* Статическая glibc из Ubuntu позволяет использовать готовый GCC. Musl
  уменьшит бинарник, но потребует отдельного toolchain. Это следующий выбор.
* BusyBox init уже обрабатывает детей, повторный запуск shell и выключение;
  писать собственный постоянный PID 1 пока нет причины. Systemd/OpenRC/runit
  рассмотрим, когда появятся реальные сервисы.

## Решение

Linux 6.12.111 LTS и BusyBox 1.37.0 из официальных tarballs с SHA256,
OpenPGP-подпись Linux; минимальные configs хранятся в проекте. BusyBox
собирается статически. Наш `/init` монтирует необходимые виртуальные FS
и передаёт PID 1 BusyBox init. QEMU напрямую загружает bzImage и cpio.gz.

Одна архитектура x86_64, TCG, serial console, 256 МБ RAM, без дисков и сети.
Rootfs mutable, но только в оперативной памяти. Выбор будущих bootloader,
libc, сервисной модели и persistent-rootfs не фиксируется этим решением.

## Проверка

Boot-тест сверяет hashes образов, ждёт SYSTEM_READY, выполняет команды в
shell, проверяет виртуальные FS и запись в `/tmp`, затем требует штатное
выключение QEMU. Один напечатанный маркер не считается достаточным.

Источники: [Linux LTS](https://www.kernel.org/),
[initramfs](https://docs.kernel.org/admin-guide/initrd.html),
[BusyBox](https://busybox.net/FAQ.html),
[подписи Linux](https://www.kernel.org/signature.html).
