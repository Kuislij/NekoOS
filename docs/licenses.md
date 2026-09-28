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
| zlib | 1.3.2 | `LICENSE` в upstream tarball и `/usr/share/licenses/zlib/LICENSE` в пакете; Zlib |
| libxkbfile | 1.2.0 | `COPYING` в upstream tarball и `/usr/share/licenses/libxkbfile/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| xkbcomp | 1.5.0 | `COPYING` в upstream tarball и `/usr/share/licenses/xkbcomp/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| xkeyboard-config | 2.48 | `COPYING` в upstream tarball и `/usr/share/licenses/xkeyboard-config/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| libfontenc | 1.1.9 | `COPYING` в upstream tarball и `/usr/share/licenses/libfontenc/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| libXfont2 | 2.0.9 | `COPYING` в upstream tarball и `/usr/share/licenses/libxfont2/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| font-misc-misc | 1.1.3 | `COPYING` в upstream tarball и `/usr/share/licenses/font-misc-misc/COPYING` в пакете; шрифты объявлены public domain, метаданные `NOASSERTION` |
| libxcvt | 0.1.3 | `COPYING` в upstream tarball и `/usr/share/licenses/libxcvt/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| libpciaccess | 0.19 | `COPYING` в upstream tarball и `/usr/share/licenses/libpciaccess/COPYING` в пакете; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| libdrm | 2.4.134 | уведомления в upstream `meson.build` и `xf86drm.c`, сохранённые в `/usr/share/licenses/libdrm/` в пакете; метаданные `NOASSERTION` |
| libsha1 | 0.3 | `COPYING` в upstream archive и `/usr/share/licenses/libsha1/COPYING` в пакете; разрешительные условия или GPL-альтернатива, метаданные `NOASSERTION` |
| xorg-server | 21.1.24 | `COPYING` в upstream tarball и `/usr/share/licenses/xorg-server/COPYING` в образе; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| libevdev | 1.13.7 | `COPYING` в upstream tarball и `/usr/share/licenses/libevdev/COPYING` в образе; условия указаны в полном уведомлении пакета |
| mtdev | 1.1.7 | `COPYING` в upstream tarball и `/usr/share/licenses/mtdev/COPYING` в образе; MIT |
| xf86-input-evdev | 2.11.0 | `COPYING` в upstream tarball и `/usr/share/licenses/xf86-input-evdev/COPYING` в образе; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| Meson (только на хосте) | 1.10.1 | `COPYING` в upstream tarball; Apache-2.0 |
| xcb-proto (только на хосте) | 1.17.0 | `COPYING` в upstream tarball; разрешительная лицензия в стиле MIT |
| pkgconf (только на хосте) | 2.5.1 | `COPYING` в upstream tarball; ISC |

Версии Linux/BusyBox/musl/TinyCC и URL находятся в `configs/sources.sh`;
Pixman, компоненты X11/Xorg и инструменты сборки закреплены в `recipes/`.
Извлечённые исходники доступны в `build/sources/`. Host GCC/Make/QEMU не
входят в образ; TinyCC входит. Linux UAPI headers создаются из закреплённого
исходного дерева Linux и имеют условия из его `LICENSES/`.

Сейчас бинарные образы собираются локально и не публикуются в Git.
До публичного распространения бинарников нужно подготовить комплект
соответствующих исходников, конфигураций и уведомлений о лицензиях.
Эта таблица не заменяет upstream license files.

Лицензия собственных файлов NekoOS пока не выбрана владельцем проекта;
лицензия Linux автоматически на весь репозиторий не назначается.
