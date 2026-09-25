# Rootfs

Здесь находятся исходные `/init`, `/etc` и `/usr/bin/neko-help`. Сценарий
image.sh создаёт `build/rootfs/`, добавляет статический BusyBox в `/usr/bin`,
ссылки на applets, каталоги и device nodes через fakeroot, затем упаковывает
всё в cpio.gz. Layout подробно описан в `docs/filesystem.md`.
Этот README не включается в образ. Не запускайте guest `/init` на хосте.
Изменения в сгенерированном `build/rootfs/` будут потеряны при новой сборке.
