# Первый графический экран: проверка 2026-09-27

Проверка выполнена в Ubuntu WSL2 и QEMU после полной сборки Linux 6.12.111,
BusyBox 1.37.0, musl 1.2.6 и нового `neko-desktop`. Собранный бинарник
статически связан с musl. `validate_image.py` принял initramfs с `desktop`,
`neko-session` и пользователем `neko` (UID/GID 1000).

`bash os test --graphics --no-build` запустил QEMU с virtio-GPU, клавиатурой и
мышью без окна на хосте. Внутри гостя появились `/dev/dri/card0`, `/dev/fb0`
и события `/dev/input/event*`; служба `desktop` запустилась. Проверка
`neko-session --check` подтвердила доступ UID/GID 1000 к домашнему каталогу,
экрану и вводу. После остановки службы `neko-session --self-test` вывел
`NEKO_DESKTOP_FRAME_READY width=1280 height=800 depth=32`; повторный запуск
службы также прошёл. Проверка завершилась штатным выключением.

`bash os test --graphics --system --no-build` повторил графическую проверку
через bootstrap и временные системный и пользовательский ext4-диски. Отдельно
прошли `bash os test --no-build`, `--services --no-build`, `--system --no-build`,
`--system-update --no-build` и `--iso --system --no-build`; восемь host unit
tests также прошли. Обычная загрузка без видеоустройства пропускает службу
`desktop` и оставляет serial shell доступным.

После проверок существующий `out/disks/system.img` обновлён командой
`bash os system-update --no-build`. Утилита проверила обновлённый образ на
временном пользовательском диске и сохранила прежнюю версию как
`system-backup-20260927T081136Z-3eeab0b0.img`. Пользовательский
`out/disks/state.img` не заменялся.

Видеокадр здесь проверен по успешной записи в framebuffer и сообщению
программы; автоматическая проверка картинки пиксель за пикселем пока не
реализована. Визуальный макет 1024×768 отдельно просмотрен после генерации
через `neko-desktop --preview`. Реальное железо, несколько окон и Wayland
пока не проверялись.
