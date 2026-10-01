# Компоненты и лицензии

## Основная Arch-база

Новая NekoOS использует официальный Arch bootstrap 2026.09.01 и подписанные
пакеты из снимка репозиториев 2026/09/29. Состав и версии 471 установленного
пакета зафиксированы в `out/arch/images/packages.lock`; список ниже относится к прежнему
musl-прототипу и не является перечнем лицензий Arch-образа.

Лицензионные сведения Arch-пакетов берутся из их метаданных, соответствующих
upstream-исходников и файлов `/usr/share/licenses/`. Сохраняются upstream
уведомления и сведения о происхождении компонентов. Для распространения
образа нужно подготовить перечень фактически включённых пакетов и исходники
или предусмотренный их лицензиями способ получения исходников; одна общая
лицензия не заменяет лицензии всех компонентов.

NekoOS — отдельный проект на базе Arch Linux. Названия Arch Linux, Xfce,
Thunar и других upstream-проектов используются для указания происхождения.
Никакие права на чужие названия и логотипы этим решением не присваиваются.
Подробности — [ADR-024](adr/0024-arch-derived-desktop-base.md).

## Live ISO

Live ISO включает свой `out/arch/iso/packages.lock`, а не список дискового
образа. Upstream-лицензии пакетов остаются в `/usr/share/licenses/`.
Шаблоны BIOS/UEFI и mkinitcpio взяты из подписанного archiso **90-1**,
лицензия **GPL-3.0-or-later**. В образе дополнительно сохранены полный
GPL-текст, `AUTHORS.rst` и [описание изменений](../live/UPSTREAM.md)
в `/usr/share/licenses/nekoos-archiso-templates/`.
Соответствующие upstream-исходники шаблонов —
[archiso v90](https://github.com/archlinux/archiso/tree/v90/configs),
собственные изменения — `scripts/arch-iso-build-root.sh` и `live/`.
Артефакт GitHub Actions предназначен для проверки разработки;
полный комплект соответствующих исходников всех включённых пакетов
и процедура публичного Release остаются отдельной задачей выпуска.

## Компоненты диагностического musl-прототипа

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
| libXrender | 0.9.12 | `COPYING` в upstream tarball и `/usr/share/licenses/libxrender/COPYING` в образе; метаданные пакета `NOASSERTION` |
| libXfixes | 6.0.2 | `COPYING` в upstream tarball и `/usr/share/licenses/libxfixes/COPYING` в образе; метаданные пакета `NOASSERTION` |
| libXrandr | 1.5.5 | `COPYING` в upstream tarball и `/usr/share/licenses/libxrandr/COPYING` в образе; метаданные пакета `NOASSERTION` |
| evilwm | 1.5 | уведомления о перераспространении в upstream `README` и `/usr/share/licenses/evilwm/README`; исторические условия aewm и 9wm, метаданные `NOASSERTION` |
| libffi | 3.5.2 | upstream `LICENSE` и `/usr/share/licenses/libffi/LICENSE` в образе; MIT |
| zlib | 1.3.2 | `LICENSE` в upstream tarball и `/usr/share/licenses/zlib/LICENSE` в пакете; Zlib |
| libpng | 1.6.58 | upstream `LICENSE` и `/usr/share/licenses/libpng/LICENSE` в образе; libpng-2.0 |
| Expat | 2.8.5 | upstream `COPYING` и `/usr/share/licenses/expat/COPYING` в образе; MIT |
| PCRE2 | 10.48 | upstream `LICENCE.md` и отдельная лицензия JIT-компилятора в `/usr/share/licenses/pcre2/`; BSD-3-Clause с исключением PCRE2 и дополнительным уведомлением |
| GLib/GObject/GIO | 2.84.4 | upstream `COPYING` и `LICENSES/` сохранены в `/usr/share/licenses/glib/`; несколько условий для библиотек и утилит, метаданные `NOASSERTION` |
| libxfce4util | 4.20.1 | upstream `COPYING` в `/usr/share/licenses/libxfce4util/COPYING`; библиотечный LGPL и GPL-код утилит, метаданные `NOASSERTION` |
| FreeType | 2.14.3 | upstream `LICENSE.TXT`, `FTL.TXT` и `GPLv2.TXT` сохранены в `/usr/share/licenses/freetype/`; выбор между FreeType License и GPLv2 или новее, метаданные `NOASSERTION` |
| Fontconfig | 2.17.1 | upstream `COPYING` в `/usr/share/licenses/fontconfig/COPYING`; несколько разрешительных уведомлений, метаданные `NOASSERTION` |
| DejaVu fonts | 2.37 | upstream `LICENSE` в `/usr/share/licenses/dejavu-fonts/LICENSE`; полные условия для шрифтов в этом файле, метаданные `NOASSERTION` |
| D-Bus | 1.16.2 | upstream `COPYING` и `LICENSES/` в `/usr/share/licenses/dbus/`; метаданные пакета `GPL-2.0-or-later`, при перераспространении учитывать также сохранённые AFL/MIT-уведомления |
| Cairo | 1.18.6 | upstream `COPYING`, `COPYING-LGPL-2.1` и `COPYING-MPL-1.1` сохранены в `/usr/share/licenses/cairo/`; альтернативные условия для библиотеки, метаданные `NOASSERTION` |
| libXi | 1.8.3 | upstream `COPYING` в `/usr/share/licenses/libxi/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| libXcursor | 1.2.3 | upstream `COPYING` в `/usr/share/licenses/libxcursor/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| libXinerama | 1.1.6 | upstream `COPYING` в `/usr/share/licenses/libxinerama/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| libXcomposite | 0.4.7 | upstream `COPYING` в `/usr/share/licenses/libxcomposite/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| libXdamage | 1.1.7 | upstream `COPYING` в `/usr/share/licenses/libxdamage/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| libXtst | 1.2.5 | upstream `COPYING` в `/usr/share/licenses/libxtst/COPYING`; разрешительные уведомления X.Org, метаданные `NOASSERTION` |
| AT-SPI2 core (ATK, AT-SPI, atk-bridge) | 2.58.9 | upstream `COPYING` в `/usr/share/licenses/at-spi2-core/COPYING`; LGPL-2.1-or-later |
| libepoxy | 1.5.10 | upstream `COPYING` в `/usr/share/licenses/libepoxy/COPYING`; MIT |
| FriBidi | 1.0.16 | upstream `COPYING` в `/usr/share/licenses/fribidi/COPYING`; LGPL-2.1-or-later |
| HarfBuzz | 12.3.0 | upstream `COPYING` в `/usr/share/licenses/harfbuzz/COPYING`; MIT и сохранённые уведомления |
| Pango | 1.56.4 | upstream `COPYING` в `/usr/share/licenses/pango/COPYING`; LGPL-2.1-or-later |
| GdkPixbuf | 2.44.8 | upstream `COPYING` в `/usr/share/licenses/gdk-pixbuf/COPYING`; LGPL-2.1-or-later |
| GTK3 | 3.24.52 | upstream `COPYING` в `/usr/share/licenses/gtk3/COPYING`; LGPL-2.1-or-later |
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
| bdftopcf (только на хосте) | 1.1.2 | `COPYING` в проверенном upstream tarball; разрешительные уведомления X.Org, инструмент не входит в образ |
| gperf (только на хосте) | 3.3 | `COPYING` в upstream tarball; сборочный инструмент Fontconfig, не входит в образ |

Версии Linux/BusyBox/musl/TinyCC и URL находятся в `configs/sources.sh`;
Pixman, компоненты X11/Xorg, шрифтовой и GTK/Xfce-зависимый слой, а также
инструменты сборки закреплены в `recipes/`.
Извлечённые исходники доступны в `build/sources/`. Host GCC/Make/QEMU не
входят в образ; TinyCC входит. Linux UAPI headers создаются из закреплённого
исходного дерева Linux и имеют условия из его `LICENSES/`.

Бинарные образы не публикуются в Git. Live ISO может быть получен
как ограниченный по сроку хранения артефакт ручной сборки GitHub Actions.
До публичного распространения бинарников нужно подготовить комплект
соответствующих исходников, конфигураций и уведомлений о лицензиях.
Эта таблица не заменяет upstream license files.

Лицензия собственных файлов NekoOS пока не выбрана владельцем проекта;
лицензия Linux автоматически на весь репозиторий не назначается.
