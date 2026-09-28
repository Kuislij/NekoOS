# Проверка минимального Xorg — 28 сентября 2026

В WSL2 Ubuntu выполнена полная сборка NekoOS с 23 системными пакетами
`NSPKG/1`, включая Xorg 21.1.24 и xf86-input-evdev 2.11.0. Источники
загружены по HTTPS с закреплёнными SHA-256; где upstream опубликовал
SHA-512, рецепты проверяют и её. Библиотеки и сервер собраны против musl
NekoOS, без зависимостей от glibc и без RPATH к дереву сборки.

Проверка initramfs приняла 5176 записей; размер сжатого образа —
10 673 672 байта. Системные пакеты установились одной транзакцией без
конфликтов. Отдельная проверочная программа в госте загрузила серверные
библиотеки, выполнила цикл сжатия zlib, а `Xorg -version` подтвердил запуск
целевого исполняемого файла через musl.

| Проверка | Результат |
| --- | --- |
| `bash os build` | `BUILD_READY` |
| `bash os test --no-build` | `BOOT_TEST_PASSED` |
| `bash os test --no-build --system` | `SYSTEM_TEST_PASSED` |
| `bash os test --no-build --graphics` | `GRAPHICS_TEST_PASSED` |
| `bash os test --no-build --graphics --system` | `GRAPHICS_SYSTEM_TEST_PASSED` |
| `bash os test --no-build --system-update` | `SYSTEM_UPDATE_TEST_PASSED` |
| `python3 tools/xorg_smoke.py` | `XORG_SMOKE_PASSED` |

Тест Xorg использует временный диск и запускает QEMU с virtio-vga,
virtio-клавиатурой и virtio-мышью. Внутри гостя он останавливает старую
framebuffer-службу, запускает Xorg на VT2 с драйвером modesetting без
glamor/GLX, находит `/dev/input/event0` и `event1`, явно подключает их через
evdev и проверяет наличие X11-сокета. Затем отдельная Xlib-программа создаёт
окно; `XGetWindowAttributes` подтверждает состояние `IsViewable`. Сервер
штатно останавливается до выключения VM. В serial log присутствуют
`XORG_CLIENT_READY`, `XORG_INPUT_READY`, `XORG_DISPLAY_READY`.

Тест подтверждает отдельный X11-клиент и загрузку драйверов ввода. Передача
событий клавиатуры и мыши самому X11-клиенту ещё не проверена. Полный сеанс
Xfce и файловый менеджер Thunar в образ пока не включены; обычный
`bash os run --graphics` по-прежнему запускает прежнюю оконную оболочку.

После проверки обновлён постоянный `out/disks/system.img`; резервная копия
прежней системы:
`out/disks/system-backup-20260928T140105Z-60a5a421.img`. Хеш SHA-256
пользовательского `out/disks/state.img` до и после обновления совпал:
`6b248847da3052a45d25f4cef0657ce3628b5da20ba90383543fe429eedf7ce7`.
