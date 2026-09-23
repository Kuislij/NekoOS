# План

Этапы 1–2 выполнены и проверены в WSL2/QEMU 2026-09-23.
Следующий scope — этап 3: устойчивый layout rootfs и проверки его состава.

1. **Готово.** WSL2/Ubuntu, зависимости, две проверки компилятора/Make/Ninja/QEMU.
2. **Готово.** Закреплённые Linux/BusyBox, SHA256, OpenPGP-подпись Linux,
   initramfs, `/init`, proc/sys/dev, serial shell, тест команд и poweroff.
3. Rootfs: определить layout `/etc`, `/usr`, `/var`, `/home`, `/tmp`, `/run`.
4. Base system: выбрать libc/init, добавить системные утилиты.
5. Формат пакета: сравнить tar.zst + metadata с альтернативами; описать
   version, architecture, license, dependencies, manifest и hashes.
6. Локальный package manager: install/remove/list/info, база и восстановление
   прерванных операций. Проверки только внутри тестового rootfs/VM.
7. Подписанные репозитории и update.
8. Собственные recipes: fetch → verify → extract → patch → build → package.
9. Изоляция сборки без сети, закрепление среды и воспроизводимость.
10. Сеть, DNS, TLS и расширенный userspace.
11. Загрузочный ISO с тестом в VM.
12. Осторожный installer — отдельный поздний проект.
13. Wayland desktop после стабильной базовой системы.
14. Проверки реального железа и подготовка к ежедневному использованию.

После появления загрузки каждый этап должен сохранять boot smoke test.
CI добавляем после устойчивого локального цикла. Self-hosting — поздняя цель.

Для этапа 3: описать владельцев и права каталогов, выбрать merged-/usr или
раздельный layout, обеспечить проверки состава rootfs и поведения после
выхода из shell. Постоянный диск и установщик не входят в этот этап.
