# Проверка сети — 2026-09-25

Среда: WSL2, Ubuntu 26.04.1, QEMU x86_64 TCG, виртуальная карта virtio-net
и пользовательская сеть QEMU. Физическая сетевая карта хоста не передавалась
гостю. Ядро Linux 6.12.111 собрано с `CONFIG_NET`, `CONFIG_INET`,
`CONFIG_PACKET`, `CONFIG_UNIX` и `CONFIG_VIRTIO_NET`.

1. `bash os build` создал initramfs с `ifconfig`, `route`, `udhcpc`, `ping`,
   `wget`, DHCP-hook и командой `neko-net-status`.
2. `bash os test --net --no-build` получил DHCP-аренду `10.0.2.15` от QEMU,
   настроил маршрут через `10.0.2.2` и DNS `10.0.2.3`. Гость отправил ICMP
   по loopback и скачал проверочный файл по HTTP с локального сервера WSL.
   Результат: `NETWORK_TEST_PASSED`. Внешние сайты тесту не нужны.
3. `bash os run --iso --net` загрузил гостя через BIOS/GRUB, получил адрес
   по DHCP и открыл `neko#`. `neko-net-status` показал адрес, маршрут и DNS;
   `ping -c 1 127.0.0.1` получил ответ. `poweroff` завершил QEMU штатно.
4. После добавления сетевого стека прежние тесты без сетевой карты прошли:
   `BOOT_TEST_PASSED`, `DISK_TEST_PASSED`, `ISO_BOOT_TEST_PASSED`.

Сейчас работает IPv4 с TCP, UDP и ICMP в QEMU. DHCP-настройка выполнена
при загрузке; обновление аренды в долгой сессии, IPv6 и HTTPS/TLS ещё не
реализованы. Проверена запись DNS-сервера, но отдельный DNS-запрос тест пока
не выполняет.
