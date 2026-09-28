# Проверка оконного X11-сеанса — 28 сентября 2026

Сборка выполнена в Ubuntu WSL2 пользователем `neko` из закреплённых
исходников. В образ добавлены libXrender 0.9.12, libXfixes 6.0.2,
libXrandr 1.5.5, evilwm 1.5 и libffi 3.5.2. Шрифты `font-misc-misc`
сконвертированы в PCF закреплённым хостовым `bdftopcf` 1.1.2.
Рецепты сверили SHA-256 и SHA-512 исходных архивов и проверили зависимости
собранных библиотек от musl без путей сборочной машины.

`bash os build` завершилось `BUILD_READY`: 28 системных пакетов, 5239 записей
в initramfs и 10 855 303 байта сжатого образа. Отдельная Xlib-программа
получила от Xorg события реальной виртуальной клавиатуры и мыши QEMU.
evilwm запустился отдельным процессом, объявил себя оконным менеджером и
управлял клиентским окном. Флаг `bash os run --x11` выбирает этот сеанс
при загрузке; проверка автозапуска прошла как из initramfs, так и с
отдельного системного диска.

| Проверка | Результат |
| --- | --- |
| `python3 -m unittest discover -s tests -v` | 25 тестов прошли |
| `bash os test --no-build` | `BOOT_TEST_PASSED`, включая вызов через libffi в гостевой системе |
| `bash os test --graphics --no-build` | `GRAPHICS_TEST_PASSED` |
| `bash os test --graphics --system --no-build` | `GRAPHICS_SYSTEM_TEST_PASSED` |
| `bash os test --system --no-build` | `SYSTEM_TEST_PASSED` |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED`, включая сохранение настроек, данных и откат |
| `python3 tools/xorg_smoke.py` | `XORG_SMOKE_PASSED`, события клавиатуры и мыши дошли до Xlib-клиента |
| `python3 tools/evilwm_smoke.py` | `EVILWM_SMOKE_PASSED`, отдельное окно управляется evilwm |
| `python3 tools/x11_autostart_smoke.py` | `X11_AUTOSTART_SMOKE_PASSED`, автозапуск и штатная остановка в обоих режимах загрузки |

Выключенный рабочий системный диск обновлён командой
`bash os system-update --no-build`. Резервная копия:
`out/disks/system-backup-20260928T144829Z-7bceb354.img`. Пользовательский
`out/disks/state.img` не изменился: SHA-256 до и после обновления —
`6b248847da3052a45d25f4cef0657ce3628b5da20ba90383543fe429eedf7ce7`.

Этот этап подтверждает настоящий многопроцессный X11-сеанс и ввод, но ещё не
полный рабочий стол: GTK, Xfce, панель и Thunar пока не собраны.
