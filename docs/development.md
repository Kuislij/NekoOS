# Среда разработки

## Текущее ограничение

2026-09-22: пользователь разрешил подготовить WSL2 и Ubuntu. Запущена
команда `wsl --install -d Ubuntu --no-launch` завершилась успешно (код 0).
Приложение Ubuntu установлено, но Linux-дистрибутив ещё не зарегистрирован:
регистрация и создание пользователя выполняются при первом запуске.
Windows успешно добавила
VirtualMachinePlatform; журнал DISM сообщает `Reboot required=yes` и
подтверждает подавление автоматической перезагрузки через `/NoRestart`.
Виртуализация в BIOS уже включена. Milestone 1 нельзя считать проверенным
до запуска компилятора и QEMU в Linux.

На Windows проверены синтаксис Bash/PowerShell, вывод справки, отказ проверки
среды вне Linux, отклонение лишних аргументов и диагностика отсутствующей
Ubuntu. Компиляция и QEMU здесь не проверены.

Инструкция Microsoft по WSL2 и Ubuntu:
https://learn.microsoft.com/windows/wsl/install
Включение компонентов Windows и перезагрузка — отдельная подготовка хоста;
скрипты проекта этого не выполняют.

## Продолжение после перезагрузки Windows

Открыть установленное приложение Ubuntu из меню «Пуск» (или `ubuntu.exe`
в PowerShell) и пройти первоначальную настройку пользователя. Затем
`wsl --list --verbose` должен показать Ubuntu с VERSION 2.
Для последующих запусков использовать `wsl -d Ubuntu`. Пароль вводится только
в терминале Ubuntu; его не нужно присылать в чат.

В Ubuntu создать отдельную рабочую копию проекта на Linux filesystem:

```bash
mkdir -p ~/src
git clone https://github.com/Kuislij/NekoOS.git ~/src/NekoOS
cd ~/src/NekoOS
bash scripts/bootstrap-dev.sh --install
bash os check
```

Если `~/src/NekoOS` уже существует, использовать существующую копию;
не удалять и не перезаписывать её для повторного запуска этих команд.
`DEV_ENV_READY` означает успешную компиляцию через Make/Ninja и запуск
QEMU в двух последовательных проходах. Общий лог: `build/logs/check-dev.log`.
При любой ошибке команда возвращает ненулевой код, маркер готовности не выводится.

После подготовки `wsl --list --verbose` должен показывать дистрибутив с
VERSION 2. Рабочую копию разместить внутри `~/src/NekoOS`, затем выполнить
команды из README. Для запуска использовать `bash os …`: это работает и
когда файлы перенесены с Windows без executable bit.

Для первого этапа нужны Bash, GCC, Make, Ninja, Git, QEMU system x86 и GNU
coreutils (timeout, tee). Bash/coreutils входят в базовую Ubuntu/Debian.
Будущие зависимости ядра будут добавлены вместе с его сборкой.

## Критерии завершения этапа 1

1. `bash os doctor` не находит пропущенных зависимостей.
2. `bash os build` компилирует и запускает C-программу через Make и Ninja.
3. `bash os run` запускает и штатно закрывает QEMU с TCG без дисков.
4. `bash os check` повторяет build/run дважды, результаты доступны в `build/logs/`.

QEMU пока проверяется в paused-состоянии, без guest kernel. На этапе 2
проверка загрузки будет ждать `SYSTEM_READY` в serial console.
Логи текущих проверок перезаписываются при следующем запуске.

Источники решений:
* Linux filesystem для сборок: https://learn.microsoft.com/windows/wsl/filesystems
* Параметры QEMU: https://www.qemu.org/docs/master/system/invocation.html
