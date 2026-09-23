# Проверка этапов 1–2 — 2026-09-23

Среда: WSL 2.7.14, Ubuntu 26.04.1 x86_64, GCC 15.2.0, Make 4.4.1,
Ninja 1.13.2, QEMU 10.2.1 с TCG. Сборка от пользователя `neko`, 4 потока.

Успешно проверено:

* `bash os check`: два прохода компиляции C через Make/Ninja и старта QEMU.
* `bash os build`: загрузка upstream, SHA256 обоих архивов, подпись Linux,
  сборка ядра и статического BusyBox, генерация initramfs без root.
* `bash os test`: SYSTEM_READY, shell, proc/sys/dev/devpts, запись в tmp,
  чтение os-release, uname, штатное poweroff и код QEMU 0.
* Повторная сборка в той же среде: SHA256 ядра и initramfs совпали.
* `bash os run`: вручную выполнены uname/os-release, проверен выход Ctrl+A → X.
* `python3 -m unittest discover -s tests -v`: повреждённый образ отклоняется
  до запуска QEMU; таймаут завершает дочерний процесс теста.
* Синтаксис Bash, guest sh, Python; Git whitespace check.

Размеры: ядро примерно 2,2 МБ, сжатый initramfs примерно 706 КиБ.
Полные конфигурации и SHA256 лежат рядом с образами в `out/images/`.
Логи находятся в `build/logs/`; это локальные артефакты, не файлы Git.

Ограничения: проверена одна среда, повторный запуск не равен независимой
чистой сборке на другой машине. Нет сети, GUI, постоянного диска, пакетов
и installer. Сборка upstream пока не изолирована sandbox. Этап 3 ещё не выполнен.
