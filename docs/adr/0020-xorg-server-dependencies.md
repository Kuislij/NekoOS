# ADR-020: минимальный Xorg для отдельного X11-клиента

Статус: Xorg собран и проверен в QEMU с отдельным Xlib-клиентом.
Дата: 2026-09-28.
Продолжает [ADR-019](0019-xlib-xext-and-xorg-milestone.md).

## Причина

Pixman и клиентские библиотеки X11 уже работают в гостевой NekoOS, но
`neko-desktop` по-прежнему рисует все окна одним процессом напрямую в
framebuffer. Для отдельного X11-клиента нужен настоящий X-сервер. Его
минимальная сборка требует обработку раскладок, шрифтов, видеорежимов и
доступ к графическому устройству. Установка бинарных библиотек Ubuntu
нарушила бы ABI musl и воспроизводимость собственных образов NekoOS.

## Решение

Для сборки минимального Xorg в очередь `NSPKG/1` добавлены пакеты из
закреплённых upstream-архивов:

| Назначение | Пакеты |
| --- | --- |
| XKB и раскладки | [libxkbfile 1.2.0](../../recipes/libxkbfile/README.md), [xkbcomp 1.5.0](../../recipes/xkbcomp/README.md), [xkeyboard-config 2.48](../../recipes/xkeyboard-config/README.md) |
| Шрифты | [zlib 1.3.2](../../recipes/zlib/README.md), [libfontenc 1.1.9](../../recipes/libfontenc/README.md), [libXfont2 2.0.9](../../recipes/libxfont2/README.md), [font-misc-misc 1.1.3](../../recipes/font-misc-misc/README.md) |
| Режимы экрана и устройства | [libxcvt 0.1.3](../../recipes/libxcvt/README.md), [libpciaccess 0.19](../../recipes/libpciaccess/README.md), [libdrm 2.4.134](../../recipes/libdrm/README.md) |
| Контрольная сумма для Xorg | [libsha1 0.3](../../recipes/libsha1/README.md) |
| X-сервер и ввод | [xorg-server 21.1.24](../../recipes/xorg-server/README.md), [libevdev 1.13.7](../../recipes/libevdev/README.md), [mtdev 1.1.7](../../recipes/mtdev/README.md), [xf86-input-evdev 2.11.0](../../recipes/xf86-input-evdev/README.md) |

Разделяемые библиотеки собраны против целевой musl; `xkbcomp` и `cvt` —
гостевые программы. `xkeyboard-config` устанавливает XKB-данные в
`/usr/share/xkeyboard-config-2` с относительной совместимой ссылкой
`/usr/share/X11/xkb`. `font-misc-misc` пока содержит два BDF-шрифта и
`fonts.dir`; для них предусмотрен backend BDF в libXfont2. В libpciaccess
отключена необязательная работа с сжатыми `pci.ids`, чтобы не зависеть от
случайной host zlib; перечисление PCI использует Linux sysfs. libdrm
собирается для общего DRM/KMS без vendor-specific API. libsha1 собирается
из точно закреплённого upstream commit 0.3 и предоставляет `libsha1.pc`
для параметра сборки Xorg `-Dsha1=libsha1`.

Xorg собран с `modesetting` и теневым framebuffer, без glamor, GLX и Mesa.
Автоматическое обнаружение устройств через udev отключено; тестовая
конфигурация указывает два QEMU event-устройства явно. Рецепт evdev точечно
исключает проверку libudev из сгенерированного `configure`, оставляя
предусмотренный upstream кодовый путь без udev. Все рецепты проверяют
контрольные суммы источников и создают архивы с лицензионными уведомлениями.
Host-инструменты используются только при сборке, их бинарники не подменяют
библиотеки в гостевом образе.

## Граница результата

Полная сборка образа прошла проверку initramfs из 5176 записей. В одноразовой
QEMU VM `tools/xorg_smoke.py` остановил framebuffer-службу, запустил Xorg
на virtio-GPU, убедился в загрузке evdev-драйверов и подключил отдельную
Xlib-программу, создавшую видимое окно. Затем сервер был штатно остановлен.
Базовая, системная и графические проверки обоих режимов, а также обновление
системного диска с откатом прошли. Отдельный X11-клиент пока не проверял
события клавиатуры и мыши; тест доказал загрузку драйверов. `bash os run
--graphics` по-прежнему показывает однопроцессный framebuffer-прототип.
Xfce, Thunar и их GTK/Cairo/D-Bus-зависимости остаются следующим этапом.
