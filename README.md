# NekoOS

Минимальная Linux-based ОС для x86_64. Уже загружается в QEMU до консоли
`neko#`: Linux 6.12.111 + статический BusyBox 1.37.0 + собственный initramfs.
Сейчас это среда для разработки базовой системы, без GUI, сети и установки
на диск. Всё состояние гостя находится в RAM и исчезает после выключения.

## Быстрый старт

В Ubuntu / Debian x86_64, в обычной учётной записи Linux:

```bash
git clone https://github.com/Kuislij/NekoOS.git ~/src/NekoOS
cd ~/src/NekoOS
bash scripts/bootstrap-dev.sh --install
bash os check
bash os build
bash os test --no-build
bash os run
```

Для сборки нужны Linux filesystem, несколько ГБ свободного места и интернет
при первом скачивании исходников. На Windows используйте WSL2; не собирайте
в `/mnt/c` или `/mnt/f`. По умолчанию сборка использует 4 потока, например
`JOBS=2 bash os build` уменьшает нагрузку. Root для сборки не нужен.

В подготовленной среде этого проекта откройте PowerShell:

```powershell
wsl -d Ubuntu -u neko --cd /home/neko/src/NekoOS
```

Затем `bash os run`. Выход из QEMU: **Ctrl+A, затем X**; штатное выключение
гостя: `poweroff`. Команды `uname -r`, `cat /etc/os-release`, `ls /` работают
в гостевой консоли. Сетевая карта, физические диски и общие папки к VM не подключены.

## Команды

| Команда | Результат |
| --- | --- |
| `bash os doctor` | Проверка доступности инструментов |
| `bash os check` | Два теста компилятора, Make/Ninja и старта QEMU |
| `bash os build` | Проверка исходников, сборка ядра, BusyBox, initramfs |
| `bash os run` | Инкрементальная сборка и интерактивная serial console |
| `bash os test` | Сборка и автоматический тест гостя |
| `bash os test --no-build` | Тест уже собранных файлов с проверкой их SHA256 |

Результаты: `out/images/bzImage`, `initramfs.cpio.gz`, конфигурации и
`SHA256SUMS`. Логи: `build/logs/build.log`, `serial.log`, `boot-test.log`,
`check-dev.log`. Эти файлы, сборки и кэш исключены из Git.

Тест загрузки ждёт `SYSTEM_READY`, выполняет команды в shell, проверяет
файловые системы и запись в `/tmp`, затем требует успешное выключение.
При успехе выводит `BOOT_TEST_PASSED`; таймаут или ошибка дают ненулевой код.

[Среда и проверки](docs/development.md) · [Архитектура](docs/architecture.md) ·
[План](docs/roadmap.md) · [Безопасность](docs/security.md) · [Лицензии](docs/licenses.md)

[Результаты проверок этапов 1–2](docs/validation-2026-09-23.md).
