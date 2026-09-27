# Компоненты и лицензии

| Компонент | Версия | Источник сведений о лицензии |
| --- | --- | --- |
| Linux | 6.12.111 | `COPYING` и `LICENSES/` в upstream tarball; GPL-2.0 |
| BusyBox | 1.37.0 | `LICENSE` в upstream tarball; GPL-2.0 |
| musl | 1.2.6 | `COPYRIGHT` в upstream tarball; MIT и указанные там дополнительные уведомления |
| TinyCC | 0.9.27 | `COPYING` и `RELICENSING` в upstream tarball; LGPL-2.1 с частично перелицензированным кодом |
| Pixman | 0.46.4 | `COPYING` в upstream tarball и `/usr/share/licenses/pixman/COPYING` в образе; MIT |
| Meson (только на хосте) | 1.10.1 | `COPYING` в upstream tarball; Apache-2.0 |

Версии Linux/BusyBox/musl/TinyCC и URL находятся в `configs/sources.sh`;
Pixman и Meson закреплены в `recipes/pixman/build.sh`.
Извлечённые исходники доступны в `build/sources/`. Host GCC/Make/QEMU не
входят в образ; TinyCC входит. Linux UAPI headers создаются из закреплённого
исходного дерева Linux и имеют условия из его `LICENSES/`.

Сейчас бинарные образы собираются локально и не публикуются в Git.
До публичного распространения бинарников нужно подготовить комплект
соответствующих исходников, конфигураций и уведомлений о лицензиях.
Эта таблица не заменяет upstream license files.

Лицензия собственных файлов NekoOS пока не выбрана владельцем проекта;
лицензия Linux автоматически на весь репозиторий не назначается.
