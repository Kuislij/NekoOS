# NekoOS

Минимальная Linux-based ОС для x86_64. Уже загружается в QEMU до консоли
`neko#`: Linux 6.12.111 + статический BusyBox 1.37.0. Доступна загрузка
из initramfs или с отдельного виртуального системного диска.
В образ включены `sh`, компилятор C TinyCC 0.9.27 и musl 1.2.6 с заголовками.
BusyBox и TinyCC собраны с musl; программы, созданные внутри NekoOS,
тоже используют её.
Теперь есть виртуальный диск для пользовательских файлов. Это среда для
разработки базовой системы, пока без GUI и установки на физический диск.
Виртуальная сеть доступна по флагу `--net`.

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

Затем `bash os run`. При первом запуске создаётся виртуальный диск на 512 МиБ
в `out/disks/state.img` внутри Linux-копии проекта. Приглашение `neko#`
означает, что можно вводить команды. Например:

```sh
echo Привет > ~/hi
cat ~/hi
poweroff
```

После следующего `bash os run` команда `cat ~/hi` снова покажет `Привет`.
При запуске shell открывается в `/root`, так что файл `hi` без `~/` тоже
сохранится. Сохраняются `/root`, `/home`, `/var/lib` и `/usr/local`;
файлы в `/tmp` и изменения системных каталогов вроде `/etc` в обычном режиме
исчезают после выключения. Режим `--system` сохраняет и системные каталоги.
`neko-help` показывает ещё несколько примеров. Штатное выключение —
`poweroff`. Для экстренного выхода из QEMU: **Ctrl+A, затем X**; после него
лучше проверить файловую систему при следующем запуске, как после внезапного
отключения питания. По умолчанию сетевая карта к VM не подключена;
физические диски и общие папки не подключаются никогда.

### Системный раздел на диске

Для загрузки с отдельного виртуального ext4-диска внутри QEMU запустите:

```bash
bash os run --system
```

При первом запуске появится отдельный `out/disks/system.img` на 256 МиБ.
Маленький загрузочный образ найдёт его и передаст управление системе на диске.
Существующий `out/disks/state.img` остаётся вторым диском: ваши файлы в
`/root`, `/home`, `/usr/local` и `/var/lib` доступны в обоих режимах. В режиме
`--system` изменения `/etc` и основной части `/usr` тоже переживают выключение.
Например, в консоли `neko#`:

```sh
echo готово > /etc/neko/notice
poweroff
```

После нового `bash os run --system` выполните `cat /etc/neko/notice`.
Обычный `bash os run` продолжает загружать систему из initramfs и не показывает
изменения её `/etc`. Сборка создаёт новую заготовку системного диска, но **не
перезаписывает существующий `system.img`**. Поэтому изменения исходного кода
пока не обновляют уже созданный системный диск автоматически. Сохраните его
копию перед ручным пересозданием; механизм обновления и переноса настроек —
следующий этап. Режим `--system` нельзя сочетать с `--ram`; через BIOS и GRUB
он запускается командой `bash os run --iso --system`.

### Локальные программы и службы

Программы в `/usr/local/bin` сохраняются на виртуальном диске и доступны
по имени команды после следующей загрузки. Для проверки в `neko#`:

```sh
printf '#!/bin/sh\necho NekoOS\n' > /usr/local/bin/hello-neko
chmod +x /usr/local/bin/hello-neko
hello-neko
neko-service list
neko-service list --all
neko-service status network
```

После `poweroff` и нового `bash os run` команда `hello-neko` по-прежнему
работает. При загрузке BusyBox init запускает `neko-service`: сначала
встроенные службы, затем включённые локальные. Сетевая служба включена по
умолчанию; `neko-service disable network` отключит её при следующей загрузке,
а `neko-service enable network` включит обратно. Ручные `start|stop|restart`
действуют сразу и не меняют автозапуск. `list --all` показывает также
отключённые службы. Настройки автозапуска сохраняются только при запуске с
виртуальным диском; режим `--ram` не принимает `enable` и `disable`.

Собственную службу можно положить на сохраняемый диск:

```sh
cat > /usr/local/etc/neko/services/hello <<'EOF'
#!/bin/sh
case "$1" in
  start) echo hello >> /var/lib/hello-service.log ;;
  status) test -f /var/lib/hello-service.log && echo 'hello: started' ;;
  stop) : ;;
  *) exit 2 ;;
esac
EOF
chmod +x /usr/local/etc/neko/services/hello
neko-service enable hello
poweroff
```

После следующего `bash os run` проверьте `cat /var/lib/hello-service.log`.
`neko-service disable hello` остановит её **автозапуск** со следующего раза;
текущий процесс при необходимости остановите `neko-service stop hello`.
Скрипты служб запускаются от root, поэтому добавляйте только доверенный код.
Ошибка запуска отдельной службы выводит `SERVICE_FAILED:имя`, а консоль остаётся
доступной; `neko-service status имя` показывает сбой текущей загрузки.
В обычном режиме основная часть `/usr` и `/etc` приходит из initramfs;
в режиме `--system` — с отдельного системного диска.

### Пакеты

NekoPkg устанавливает одну команду в сохраняемый `/usr/local`.
В консоли `neko#` попробуйте встроенный пример:

```sh
neko-pkg info /usr/share/nekoos/packages/neko-greet-0.1.0.npkg
neko-pkg install /usr/share/nekoos/packages/neko-greet-0.1.0.npkg
neko-greet
neko-pkg upgrade /usr/share/nekoos/packages/neko-greet-0.2.0.npkg
neko-pkg install /usr/share/nekoos/packages/neko-companion-1.0.0.npkg
neko-companion
neko-pkg list
neko-pkg verify neko-greet
neko-pkg remove neko-companion
neko-pkg remove neko-greet
```

Установленная команда работает и после следующего запуска. Если она уже
установлена, повторите `neko-greet` и `neko-pkg list` без новой установки.
Установка требует обычного запуска с виртуальным диском, не `--ram`.
Менеджер отклоняет повреждённый архив, сверяет SHA-256 и не заменяет чужую
команду с тем же именем. Новый формат NekoPkg/2 поддерживает требования к
минимальной версии уже установленного пакета; зависимости сначала ставятся
вручную. `upgrade` переключает команду на новую версию без промежутка,
когда она недоступна. Если `neko-greet` уже установлен, начните с `list` и
перейдите к обновлению. Пакет пока содержит один исполняемый файл;
автоматической загрузки зависимостей и сетевых репозиториев ещё нет.
Как собрать свой пакет и добавить его в образ, описано в
[packages/README.md](packages/README.md).

### Сеть

Включите виртуальную сеть при запуске:

```bash
bash os run --net
```

После появления `neko#`:

```sh
neko-net-status
ping -c 1 127.0.0.1
```

Гостевая система получает IPv4-адрес, маршрут и DNS от виртуального DHCP
QEMU. Поддерживаются IPv4, TCP, UDP, ICMP и HTTP-клиент `wget`; сеть работает
также с `bash os run --iso --net` и `bash os run --ram --net`. QEMU использует
сеть пользовательского режима с исходящими подключениями, без открытых
портов для входящих соединений. HTTPS/TLS, IPv6 и обновление DHCP-аренды в
долгих сессиях пока не настроены.

### Загрузка через BIOS и GRUB

Для проверки полного пути загрузки в виртуальной машине соберите ISO и
запустите его с тем же виртуальным диском:

```bash
bash os build
bash os iso
bash os test --iso --no-build
bash os run --iso
```

`bash os run --iso` сам пересобирает ядро и ISO; `bash os iso` использует уже
собранные файлы. В консоли `neko#` команда `neko-boot-status` показывает,
обнаружены ли процессоры, RAM, прерывания, таблицы ACPI, виртуальный диск и
ext4. Обычный ISO загружает систему из initramfs. Для полного пути
BIOS → GRUB → системный диск используйте:

```bash
bash os iso --system
bash os test --iso --system --no-build
bash os run --iso --system
```

Второй образ `NekoOS-system.iso` выбирает пункт системного диска по умолчанию.
В режиме `--system` команды берутся из существующего `system.img`; новый ISO
сам по себе не обновляет программы на этом диске.
Оба ISO предназначены для виртуального BIOS в QEMU; это пока не установочные
образы и не образы для UEFI.
Физические диски компьютера не используются.

### Программа на C внутри NekoOS

Сначала можно собрать готовый пример в консоли `neko#`:

```sh
cc /usr/share/nekoos/examples/hello.c -o hello
./hello
```

Чтобы написать свой вариант, создайте исходный файл и соберите его:

```sh
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) {
    puts("Hello from NekoOS");
    return 0;
}
EOF
cc hello.c -o hello
./hello
```

`cc` запускает TinyCC. Программа использует заголовок `<stdio.h>` и C-библиотеку
musl. Файлы `hello.c` и `hello` останутся в `/root` после `poweroff`.
Это начальный C toolchain, не полный GCC/Clang и не среда для C++.
Используйте обычную сборку `cc hello.c -o hello`: флаг `-static` в текущей
комбинации TinyCC/musl пока не поддерживается надёжно.

## Команды

| Команда | Результат |
| --- | --- |
| `bash os doctor` | Проверка доступности инструментов |
| `bash os check` | Два теста компилятора, Make/Ninja и старта QEMU |
| `bash os build` | Проверка исходников, сборка ядра, BusyBox, initramfs |
| `bash os image` | Создать виртуальный диск, если его ещё нет; существующие файлы не стирает |
| `bash os system-image` | Создать системный диск из текущей сборки, если его ещё нет |
| `bash os iso` | Создать загрузочный BIOS ISO из уже собранных ядра и initramfs |
| `bash os iso --system` | Создать BIOS ISO с системным диском как пунктом по умолчанию |
| `bash os run` | Сборка и консоль с сохранением файлов |
| `bash os run --system` | Загрузиться с сохраняемого системного ext4-диска |
| `bash os run --iso` | Сборка и запуск через виртуальный BIOS и GRUB |
| `bash os run --iso --system` | Загрузиться через BIOS и GRUB с системного диска |
| `bash os run --net` | Включить виртуальную сеть, DHCP и исходящие подключения |
| `bash os run --ram` | Временная консоль без диска; файлы исчезают после выключения |
| `bash os run --verbose` | Сборка и полный вывод ядра при загрузке |
| `bash os test` | Сборка и автоматический тест временной гостевой системы |
| `bash os test --disk` | Две загрузки с проверкой сохранённого файла |
| `bash os test --iso` | Две загрузки ISO через BIOS и GRUB, проверка оборудования и данных |
| `bash os test --iso --system` | Две загрузки системного диска через BIOS и GRUB на временных дисках |
| `bash os test --net` | Проверить DHCP, DNS-настройку, ICMP и HTTP в QEMU |
| `bash os test --services` | Проверить сохранение настроек служб на отдельном временном диске |
| `bash os test --system` | Две загрузки с отдельных временных системного и пользовательского дисков |
| `bash os test --package` | Проверить установку, зависимости, обновление и удаление на отдельном тестовом диске |
| `bash os test --no-build` | Тест уже собранных файлов с проверкой их SHA256 |

Результаты: `out/images/bzImage`, `initramfs.cpio.gz`,
`bootstrap.cpio.gz`, `system-template.img`, `NekoOS.iso`, `NekoOS-system.iso`,
конфигурации и контрольные суммы. Логи: `build/logs/build.log`, `serial.log`,
`boot-test.log`, `disk-test-*.log`, `iso-test-*.log`, `iso-system-test-*.log`, `network-test.log`,
`services-test-*.log`, `system-test-*.log`, `package-test-*.log`, `check-dev.log`.
Полный вывод сборки
при `os run` также находится в `run-build.log`. Сборки, кэш, логи и
виртуальные диски исключены из Git. **Не удаляйте `out/disks/state.img` или
`out/disks/system.img`, если нужны сохранённые файлы.** Для резервной копии
сначала выключите VM, затем скопируйте нужный файл целиком.

Перед загрузкой проверяется содержимое initramfs. Тест ждёт `SYSTEM_READY`,
выполняет команды в shell, компилирует и запускает C-программу, проверяет
файловые системы, каталоги и запись в `/tmp`, затем требует успешное выключение.
При успехе выводит `BOOT_TEST_PASSED`; таймаут или ошибка дают ненулевой код.

[Среда и проверки](docs/development.md) · [Файловая система](docs/filesystem.md) ·
[Архитектура](docs/architecture.md) ·
[План](docs/roadmap.md) · [Безопасность](docs/security.md) · [Лицензии](docs/licenses.md)

[Результаты проверок этапов 1–2](docs/validation-2026-09-23.md).
[Результаты проверки этапа 3](docs/validation-2026-09-25.md).
[Проверка сохраняемого диска](docs/validation-persistence-2026-09-25.md).
[Проверка C toolchain](docs/validation-c-toolchain-2026-09-25.md).
[Проверка загрузки через BIOS и GRUB](docs/validation-boot-2026-09-25.md).
[Проверка сети](docs/validation-network-2026-09-25.md).
[Проверка локальных программ и служб](docs/validation-services-2026-09-25.md).
[Проверка сохраняемых служб](docs/validation-persistent-services-2026-09-26.md).
[Проверка системного диска](docs/validation-system-disk-2026-09-26.md).
[Проверка BIOS-загрузки с системного диска](docs/validation-iso-system-2026-09-26.md).
[Проверка единой musl в базовой системе](docs/validation-musl-2026-09-26.md).
[Проверка первого формата пакетов](docs/validation-packages-2026-09-26.md).
[Проверка зависимостей и обновления](docs/validation-package-upgrades-2026-09-26.md).
