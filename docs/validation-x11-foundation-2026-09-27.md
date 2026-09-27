# Проверка клиентской основы X11 — 27 сентября 2026

Сборка выполнена в Ubuntu WSL2 пользователем `neko` из закреплённых
upstream-исходников. В системный `/usr` добавлены Pixman 0.46.4,
xorgproto 2025.1, libXau 1.0.12, libXdmcp 1.1.5 и libxcb 1.17.0.
Построенные только для хоста xcb-proto 1.17.0 и pkgconf 2.5.1 в гостевой
образ не входят. Рецепты проверили контрольные суммы источников; для
libxcb, xorgproto, libXau и libXdmcp также сверены опубликованные SHA-512.

`bash os build` завершилось `BUILD_READY`. Проверка initramfs приняла
4147 записей; сжатый образ имеет размер 6 666 371 байт. У libxcb
SONAME `libxcb.so.1`, динамические зависимости `libXau.so.6`,
`libXdmcp.so.6` и `libc.so`; библиотека и проверочные программы не содержат
RPATH/RUNPATH и используют загрузчик musl. Программы вызывают функции
Pixman, Xau/Xdmcp и XCB внутри гостевой системы. Тест XCB не требует
запущенного X-сервера.

| Проверка | Результат |
| --- | --- |
| `python3 -m unittest discover -s tests -v` | 25 тестов прошли, включая проверку версий, отсутствующих зависимостей, циклов и недоверенных записей `NSPKG/1` |
| `bash os test --no-build` | `BOOT_TEST_PASSED`, гостевые маркеры `PIXMAN_RUNTIME_READY`, `X11_BASE_RUNTIME_READY`, `XCB_RUNTIME_READY` |
| `bash os test --system --no-build` | `SYSTEM_TEST_PASSED` |
| `bash os test --graphics --no-build` | `GRAPHICS_TEST_PASSED`, прежняя оболочка работает |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED`, временный системный диск загружается с тремя библиотечными проверками, затем откатывается |

После проверок существующий выключенный `out/disks/system.img` обновлён через
`bash os system-update --no-build`. Резервная копия:
`out/disks/system-backup-20260927T191619Z-1264119e.img`. Пользовательский
`state.img` не подключался к проверке обновления; SHA-256 до и после совпал:
`6b248847da3052a45d25f4cef0657ce3628b5da20ba90383543fe429eedf7ce7`.

Сборка и эти тесты подтверждают доступность первых библиотек X11 в NekoOS.
Полноценные Xorg, Xfce и Thunar ещё не собраны и графический сеанс X11 здесь
не проверялся.
