# Проверка пакетной, сервисной и графической основы

Дата: 2026-09-26. Среда: Ubuntu в WSL2, QEMU с TCG, Linux x86_64.
Сборка `bash os build` завершилась `BUILD_READY`; контрольный анализ
initramfs нашёл 1430 записей и прошёл. Тесты выполнялись с `--no-build`
после этой сборки, на отдельных временных дисках там, где это требуется.

| Команда | Результат |
| --- | --- |
| `python3 -m unittest tests/test_multifile_package.py` | 3 теста, OK |
| `python3 tools/test_neko_service_lifecycle.py` | 2 теста, OK |
| `bash os test --package --no-build` | `PACKAGE_TEST_PASSED` |
| `bash os test --services --no-build` | `SERVICES_TEST_PASSED` |
| `bash os test --graphics --no-build` | `GRAPHICS_TEST_PASSED` |
| `bash os test --net --no-build` | `NETWORK_TEST_PASSED` |
| `bash os test --system --no-build` | `SYSTEM_TEST_PASSED` |
| `bash os test --system-update --no-build` | `SYSTEM_UPDATE_TEST_PASSED` |
| `bash os test --no-build` | `BOOT_TEST_PASSED` |
| `bash os test --iso --system --no-build` | `ISO_SYSTEM_TEST_PASSED` |

Тест пакетов установил NekoPkg/3 с отдельным ресурсом, проверил устойчивый
путь, обновил обе части на новую версию, обнаружил повреждение ресурса и
удалил пакет. Он также сохранил совместимость NekoPkg/1 и /2 и отказался
заменить пользовательский каталог. Тест служб прошёл автозапуск,
`start/status/stop/restart` долгоживущего процесса и восстановление после
ошибки другой службы. Графический тест увидел `/dev/dri/card0` и события
клавиатуры/мыши. Он запускается без видимого окна; GTK-режим QEMU также
проверен отдельным коротким стартом.

Рабочий `out/disks/system.img` обновлён командой `bash os system-update
--no-build`; предыдущая версия сохранена как
`system-backup-20260926T181624Z-bb2f6093.img`. `state.img` команда не
подключала. Готового GUI, управления пользовательскими сеансами и
автоматической загрузки зависимостей на этом этапе ещё нет.
