# Проверка библиотечной основы рабочего стола — 29 сентября 2026

В этот этап NekoOS добавлены десять системных пакетов `NSPKG/1`: libpng
1.6.58, Expat 2.8.5, PCRE2 10.48, GLib/GObject/GIO 2.84.4,
libxfce4util 4.20.1, FreeType 2.14.3, Fontconfig 2.17.1, DejaVu 2.37,
Cairo 1.18.6 и D-Bus 1.16.2. Проверенный образ содержит 38 системных
пакетов и 5999 записей initramfs. Архивы исходников
закреплены хешами в рецептах; пакеты содержат собственные манифесты и
уведомления о лицензиях. Зависимости проверяются при сборке образа.

| Проверка | Результат |
| --- | --- |
| `bash os build` | `BUILD_READY`; валидатор принял 38 пакетов и 5999 записей initramfs |
| `bash os test --no-build` | `BOOT_TEST_PASSED` в QEMU на образе из 38 пакетов и 5999 записей; вызовы новых разделяемых библиотек выполняются гостевыми musl-программами |
| Гостевой `neko-libpng-check` | `LIBPNG_RUNTIME_READY`: запись и чтение PNG с RGBA-пикселями |
| Гостевые `neko-expat-check`, `neko-pcre2-check` | `EXPAT_RUNTIME_READY`, `PCRE2_RUNTIME_READY`: XML и регулярные выражения |
| Гостевые `neko-freetype-check`, `neko-fontconfig-check` | `FREETYPE_RUNTIME_READY`, `FONTCONFIG_RUNTIME_READY`; Fontconfig находит упакованный шрифт DejaVu |
| Гостевые `neko-glib-check`, `neko-libxfce4util-check` | `GLIB_RUNTIME_READY`, `LIBXFCE4UTIL_RUNTIME_READY`: GLib/GObject/GIO и первая библиотека Xfce |
| `bash recipes/cairo/build.sh` | Повторная сборка дала тот же SHA-256 пакета; musl-проба нарисовала и прочитала PNG через Cairo, проверила Cairo-GObject |
| Гостевой `neko-cairo-check /tmp/neko-cairo.png` | `CAIRO_SMOKE_OK` в QEMU: Cairo нарисовал PNG и проверил Cairo-GObject уже внутри NekoOS |
| Гостевой `dbus-run-session -- gdbus call --session ...` | `DBUS_SESSION_READY`: ответ пользовательской шины D-Bus |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED`: обновление, пользовательские файлы и откат |
| `python3 tools/evilwm_smoke.py` | `EVILWM_SMOKE_PASSED`: окно в сеансе Xorg + evilwm, запрос к D-Bus |
| `python3 tools/x11_autostart_smoke.py` | `X11_AUTOSTART_SMOKE_PASSED`: автозапуск с обоих типов образа, запрос к пользовательской шине и остановка службы |
| `bash os test --graphics --system --no-build` | `GRAPHICS_SYSTEM_TEST_PASSED`: графический сеанс с записью файла на системный диск |
| `bash os test --system --no-build` | `SYSTEM_TEST_PASSED`: загрузка с диска и сохранение файлов после выключения |
| `python3 -m unittest discover -s tests -q` | 25 проверок прошли |

Проверки выполняют функции библиотек и запросы к настоящему
`dbus-daemon`, а не только ищут файлы в образе. Хостовые библиотеки не
подставляются в гостевую систему. Текущий `--x11` остаётся промежуточным
сеансом Xorg + evilwm. GTK 3, панель и сеанс Xfce, `xfdesktop` и Thunar
ещё не собраны; наличие `libxfce4util` само по себе не создаёт рабочий стол.
Следующий порядок сборки зафиксирован в
[ADR-022](adr/0022-gtk-xfce-foundation.md) на основе
[официального руководства Xfce](https://docs.xfce.org/xfce/4.20/building).
