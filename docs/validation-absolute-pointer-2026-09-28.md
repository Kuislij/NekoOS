# Проверка управления указателем — 28 сентября 2026

Графический запуск QEMU переведён с относительной `virtio-mouse-pci` на
абсолютную `virtio-tablet-pci`. Это позволяет направлять курсор в гостевую
систему без захвата мыши окном QEMU. Xorg находит устройство Tablet через
evdev. Прежняя framebuffer-оболочка читает диапазоны `ABS_X` и `ABS_Y`
каждого устройства и переводит координаты в размеры экрана; относительная
мышь остаётся поддержанной.

Тесты вводят разные абсолютные координаты через
[QEMU QMP `input-send-event`](https://www.qemu.org/docs/master/interop/qemu-qmp-ref.html),
а не через внутренние функции NekoOS. Клиент X11 должен получить
`MotionNotify`, `ButtonPress` и `KeyPress`; прежняя оболочка подтверждает
обработку абсолютных координат вместе с проверкой создания файла через её
интерфейс.

| Проверка | Результат |
| --- | --- |
| `python3 -m unittest discover -s tests -q` | 25 тестов прошли |
| `bash os build` | `BUILD_READY`, initramfs прошёл проверку 5239 записей |
| `bash os test --no-build` | `BOOT_TEST_PASSED` |
| `bash os test --graphics --no-build` | `GRAPHICS_TEST_PASSED`, абсолютное движение обработано |
| `bash os test --graphics --system --no-build` | `GRAPHICS_SYSTEM_TEST_PASSED`, тот же ввод с системного диска |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED` на временных дисках |
| `python3 tools/xorg_smoke.py` | `XORG_SMOKE_PASSED`, движение, щелчок и клавиша доставлены Xlib-клиенту |
| `python3 tools/evilwm_smoke.py` | `EVILWM_SMOKE_PASSED` |
| `python3 tools/x11_autostart_smoke.py` | `X11_AUTOSTART_SMOKE_PASSED` из initramfs и с системного диска |

Открытая до изменения виртуальная машина продолжает использовать прежнее
устройство ввода. Исправление применяется при следующем запуске QEMU.
После штатного выключения гостевой системы постоянный системный диск обновлён
через `bash os system-update --no-build`. Резервная копия:
`out/disks/system-backup-20260928T201108Z-73a66bde.img`.
Пользовательский `state.img` при обновлении не изменился: SHA-256 до и после —
`d05777ebde1cfefe11df14b0de86540084311084d4720f60e46173d6a57a2aa6`.
