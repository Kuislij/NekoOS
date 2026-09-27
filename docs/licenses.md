# Компоненты и лицензии

| Компонент | Версия | Источник сведений о лицензии |
| --- | --- | --- |
| Linux | 6.12.111 | `COPYING` и `LICENSES/` в upstream tarball; GPL-2.0 |
| BusyBox | 1.37.0 | `LICENSE` в upstream tarball; GPL-2.0 |
| musl | 1.2.6 | `COPYRIGHT` в upstream tarball; MIT и указанные там дополнительные уведомления |
| TinyCC | 0.9.27 | `COPYING` и `RELICENSING` в upstream tarball; LGPL-2.1 с частично перелицензированным кодом |
| Pixman | 0.46.4 | `COPYING` в upstream tarball и `/usr/share/licenses/pixman/COPYING` в образе; MIT |
| xorgproto | 2025.1 | `COPYING-*` в upstream tarball и `/usr/share/licenses/xorgproto/` в образе; набор уведомлений для протоколов и GL |
| xtrans | 1.6.0 | `COPYING` в upstream tarball и `/usr/share/licenses/xtrans/COPYING` в образе; несколько разрешительных уведомлений, метаданные пакета `NOASSERTION` |
| libXau | 1.0.12 | `COPYING` в upstream tarball и `/usr/share/licenses/libxau/COPYING` в образе; MIT-open-group |
| libXdmcp | 1.1.5 | `COPYING` в upstream tarball и `/usr/share/licenses/libxdmcp/COPYING` в образе; MIT-open-group |
| libxcb | 1.17.0 | `COPYING` в upstream tarball и `/usr/share/licenses/libxcb/COPYING` в образе; разрешительная лицензия в стиле MIT |
| libX11 | 1.8.13 | `COPYING` в upstream tarball и `/usr/share/licenses/libx11/COPYING` в образе; несколько разрешительных уведомлений, метаданные пакета `NOASSERTION` |
| libXext | 1.3.7 | `COPYING` в upstream tarball и `/usr/share/licenses/libxext/COPYING` в образе; несколько разрешительных уведомлений, метаданные пакета `NOASSERTION` |
| Meson (только на хосте) | 1.10.1 | `COPYING` в upstream tarball; Apache-2.0 |
| xcb-proto (только на хосте) | 1.17.0 | `COPYING` в upstream tarball; разрешительная лицензия в стиле MIT |
| pkgconf (только на хосте) | 2.5.1 | `COPYING` в upstream tarball; ISC |

Версии Linux/BusyBox/musl/TinyCC и URL находятся в `configs/sources.sh`;
Pixman, компоненты X11 и инструменты сборки закреплены в `recipes/`.
Извлечённые исходники доступны в `build/sources/`. Host GCC/Make/QEMU не
входят в образ; TinyCC входит. Linux UAPI headers создаются из закреплённого
исходного дерева Linux и имеют условия из его `LICENSES/`.

Сейчас бинарные образы собираются локально и не публикуются в Git.
До публичного распространения бинарников нужно подготовить комплект
соответствующих исходников, конфигураций и уведомлений о лицензиях.
Эта таблица не заменяет upstream license files.

Лицензия собственных файлов NekoOS пока не выбрана владельцем проекта;
лицензия Linux автоматически на весь репозиторий не назначается.
