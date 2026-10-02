# 1c-client — клиенты 1С в rootless podman-контейнере

Запуск клиентских приложений 1С:Предприятие 8.3 (конфигуратор, тонкий и
толстый клиент, обычное приложение) в rootless podman-контейнере на хосте
Arch Linux (KDE Plasma, Wayland), ничего не устанавливая в систему хоста.

Постановка задачи — [TASK.md](TASK.md), для агентов — [AGENTS.md](AGENTS.md).

## Как это устроено

- Образ клиента: Ubuntu 24.04 + платформа 1С, сборка —
  [client/Containerfile](client/Containerfile), инструкции —
  [docs/build.md](docs/build.md).
- Точка входа в контейнере: [client/entrypoint.sh](client/entrypoint.sh) —
  контейнер живёт, пока в нём есть процессы клиентов.
- Хостовый запуск: [bin/1c-run.sh](bin/1c-run.sh) — команды `start`,
  `stop`, `status`, `build`, `build+test`, `build+start`; инструкции —
  [docs/run.md](docs/run.md).
- Дисплей: X11-сокет XWayland + xauth; session-dbus хоста — уведомления;
  сеть — дефолтная исходящая; `--userns=keep-id`.
- Данные пользователя — в [volumes/](volumes/) (обмен файлами, профиль
  клиента, лицензия, технологический журнал).
- Ключевые решения — в [adr/](adr/): webkit-4.1 бандлы, отказ от
  LD_LIBRARY_PATH, база 24.04 (зависание 26.04), локаль ru, host-dbus.

## Быстрый старт

```bash
# 1. Собрать образ
bin/1c-run.sh build

# 2. Запустить клиента (из X-сессии KDE)
bin/1c-run.sh                                # стартовый диалог 1С (1cv8)
bin/1c-run.sh start 1cv8c /IBConnectionString 'File="..."'   # тонкий
bin/1c-run.sh start 1cv8 DESIGNER /IBConnectionString 'File="..."'  # конфигуратор
bin/1c-run.sh status                         # контейнер и процессы
bin/1c-run.sh stop                           # остановить
```

Приёмочные проверки — [docs/acceptance.md](docs/acceptance.md).

## Статус

Разведка, образ и скрипты готовы; приёмка в работе (см. TODO/ROADMAP.md).