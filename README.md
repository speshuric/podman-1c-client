# 1c-client — клиенты 1С в rootless podman-контейнере

Запуск клиентских приложений 1С:Предприятие 8 (конфигуратор, тонкий и
толстый клиент, обычное приложение) в rootless podman-контейнере на хосте
Arch Linux (KDE Plasma, Wayland), ничего не устанавливая в систему хоста.
Предположительно, можно несложно адаптировать для других дистрибутивов и окружений.

[Публикация на Infostart](https://infostart.ru/1c/articles/2807378/)

![Infostart](https://infostart.ru/bitrix/templates/sandbox_empty/assets/tpl/abo/img/logo.svg)

Постановка задачи — [TASK.md](TASK.md), для агентов — [AGENTS.md](AGENTS.md).

## Как это устроено

- Образ клиента: Ubuntu 24.04 + платформа 1С, сборка —
  [client/Containerfile](client/Containerfile), инструкции —
  [docs/build.md](docs/build.md).
- Точка входа в контейнере: [client/entrypoint.sh](client/entrypoint.sh) —
  контейнер живёт, пока в нём есть процессы клиентов.
- Хостовый запуск: [bin/1c-run.sh](bin/1c-run.sh); инструкции —
  [docs/run.md](docs/run.md).
- Дисплей: X11-сокет XWayland + xauth; session-dbus хоста — уведомления;
  сеть — дефолтная исходящая; `--userns=keep-id`.
- Данные пользователя — в [volumes/](volumes/) (обмен файлами, профиль
  клиента, лицензия, технологический журнал).
- Ключевые решения — в [adr/](adr/).

## Быстрый старт

```bash
# 0. Получить проект и дистрибутив платформы
git clone https://github.com/speshuric/podman-1c-client.git
cd podman-1c-client
#    Дистрибутив платформы (zip с сайта 1С, напр. server64_8_3_27_2342.zip)
#    распаковать в distr/1c-<версия>/ — внутри должен оказаться
#    setup-full-<версия>-x86_64.run:
mkdir -p distr/1c-8.3.27.2342
unzip server64_8_3_27_2342.zip -d distr/1c-8.3.27.2342

# 1. Собрать образ (варианты: build+test — отладочные пакеты,
#    build+breeze — Breeze GTK-тема; тег один, используется последний собранный)
bin/1c-run.sh build

#    Другая версия платформы: каталог дистрибутива distr/1c-<версия>/ и
#    переменная PLATFORM_VERSION (и там же она при запуске):
#      PLATFORM_VERSION=8.5.1.1522 bin/1c-run.sh build
#      PLATFORM_VERSION=8.5.1.1522 bin/1c-run.sh

# 2. Запустить клиента (из X-сессии KDE)
bin/1c-run.sh                                # стартовый диалог 1С (1cv8)
bin/1c-run.sh start 1cv8c /IBConnectionString 'File="..."'   # тонкий
bin/1c-run.sh start 1cv8 DESIGNER /IBConnectionString 'File="..."'  # конфигуратор
bin/1c-run.sh status                         # контейнер и процессы
bin/1c-run.sh stop                           # остановить
```

Приёмочные проверки — [docs/acceptance.md](docs/acceptance.md).

## Лицензия

MIT — [LICENSE](LICENSE). Дистрибутивы платформы 1С и сама платформа
распространяются по лицензии 1С и в проект не входят.

## Статус

см. TODO/ROADMAP.md и CHANGELOG.md
