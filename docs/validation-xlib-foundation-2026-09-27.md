# Проверка Xlib, libXext и системного образа — 27 сентября 2026

Сборка выполнена в Ubuntu WSL2 пользователем `neko`. В образ добавлены
системные пакеты xtrans 1.6.0, libX11 1.8.13 и libXext 1.3.7 из закреплённых
исходников X.Org. Рецепты сверили SHA-256 и SHA-512, а установщик `NSPKG/1`
проверил зависимости перед сборкой rootfs. Полные файлы `COPYING` сохранены в
`/usr/share/licenses/`; поскольку они содержат разные разрешительные
уведомления, поле лицензии этих пакетов имеет значение `NOASSERTION`.

`bash os build` завершилось `BUILD_READY`. Проверка initramfs приняла
4532 записи; сжатый образ имеет размер 7 778 853 байта. `libX11.so.6`
зависит от `libxcb.so.1` и musl `libc.so`, а `libXext.so.6` — от
`libX11.so.6` и musl `libc.so`. Ни одна из этих библиотек не содержит
RPATH/RUNPATH. Проверка `strings` не нашла в них абсолютного пути к
WSL-каталогу сборки; рецепт libXext также удаляет ненужные отладочные
символы. Повторная сборка в том же каталоге дала прежние SHA-256 архивов:
`67e2845a638db13866574776bdbc5629178e5f20ed02edb70ea3fc29c6a18761`
для libX11 и
`16ea4d81f5fcb3737b5a1ddfc059388ee8e8c1518c115fa46ee3c610b1ed7786`
для libXext. Проверочные программы вызывают функции Xlib и libXext в госте,
не требуя работающего X-сервера.

| Проверка | Результат |
| --- | --- |
| `python3 -m unittest discover -s tests -q` | 25 тестов прошли |
| `bash os test --no-build` | `BOOT_TEST_PASSED`, включая `XLIB_RUNTIME_READY` и `XEXT_RUNTIME_READY`; повторён после финальной сборки |
| `bash os test --system --no-build` | `SYSTEM_TEST_PASSED` |
| `bash os test --graphics --no-build` | `GRAPHICS_TEST_PASSED` |
| `bash os test --graphics --system --no-build` | `GRAPHICS_SYSTEM_TEST_PASSED`, создание файла в прежнем графическом режиме на системном диске |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED`, обновление и откат временного диска; повторён после финальной сборки |

После тестов выключенный основной `out/disks/system.img` обновлён через
`bash os system-update --no-build`. Перед заменой сохранена резервная копия
`out/disks/system-backup-20260927T201003Z-9431c555.img`. SHA-256
пользовательского `state.img` до и после обновления совпал:
`6b248847da3052a45d25f4cef0657ce3628b5da20ba90383543fe429eedf7ce7`.

Эти проверки подтверждают клиентские библиотеки X11 и сохранность прежнего
графического режима. Xorg, Xfce и Thunar в этом образе ещё нет; возможность
показывать отдельное окно X11 не проверялась.
