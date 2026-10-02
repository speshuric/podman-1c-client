# Запуск клиентов 1С

Скрипт: `bin/1c-run.sh` (на хосте), точка входа: `client/entrypoint.sh`
(в образе, `/usr/local/bin/entrypoint.sh`).

## Синтаксис

```bash
bin/1c-run.sh [команда] [аргументы...]
```

| Команда | Действие |
|---|---|
| *(без аргументов)* | запуск `1cv8` без аргументов — стартовый диалог 1С |
| `start <бинарник> [ключи 1С…]` | запуск клиента; бинарник — `1cv8c`, `1cv8` или `1cestart`; **любое другое первое слово** тоже принимается как аргумент `1cv8` (например `ENTERPRISE`, `DESIGNER`) |
| `stop` | остановить контейнер |
| `status` | статус контейнера и число процессов 1С |
| `build` | собрать рабочий образ (`MODE=run`) |
| `build+test` | собрать отладочный образ (`MODE=test`, тег `-test`) |
| `build+breeze` | собрать рабочий образ + Breeze GTK-тема (тег `-breeze`) |
| `build+start` | собрать рабочий образ и запустить клиента |
| `help` | справка по командам |

Неизвестная первая команда трактуется как `start`: удобно вызывать
сразу бинарник (`bin/1c-run.sh 1cv8c …`) или старые имена типов
(`thin`, `thick`, `designer`), которые теперь понимает 1С сама:

```bash
# стартовый диалог (1cv8 без аргументов)
bin/1c-run.sh

# тонкий клиент на файловой базе
bin/1c-run.sh start 1cv8c /IBConnectionString 'File="/home/ubuntu/Documents/InfoBase"'

# конфигуратор
bin/1c-run.sh start 1cv8 DESIGNER /IBConnectionString 'File="/home/ubuntu/Documents/InfoBase"'

# толстый клиент (обычное приложение = тот же бинарник 1cv8)
bin/1c-run.sh start 1cv8 ENTERPRISE /IBConnectionString 'File="/home/ubuntu/Documents/InfoBase"'
```

В режиме `start` при живом контейнере выполняется `podman exec -d`
(ещё одно окно в том же контейнере); при отсутствии контейнера —
`podman run --rm -d`. Если образ не собран, `start` отказывает с
подсказкой собрать (`bin/1c-run.sh build`).

Переменные окружения (опционально):

- `PLATFORM_VERSION` — версия платформы, по умолчанию `8.3.27.2342`;
  определяет образ `localhost/1c-client:<версия>` и имя контейнера
  `1c-client-<версия>`;
- `DISPLAY` — X-дисплей, по умолчанию текущий `$DISPLAY`;
- `XAUTHORITY` — xauth-файл сессии, по умолчанию текущий `$XAUTHORITY`.

## Жизненный цикл

- Контейнера нет → `podman run --rm -d --userns=keep-id` с томами,
  X11-сокетом и host-dbus; клиент стартует внутри.
- Контейнер уже жив → `podman exec -d` в него — поднимается ещё одно
  окно в том же контейнере.
- Контейнер гаснет сам, когда последний клиентский процесс завершён
  (entrypoint как PID 1 раз в 2 секунды проверяет `pgrep 1cv8`).
- `stop`/`podman stop` реагируют на SIGTERM мгновенно.
- Скрипт ничего не ждёт и не отслеживает: запустили и забыли.

## Тома (`volumes/`)

| Каталог хоста | В контейнере | Содержимое |
|---|---|---|
| `volumes/home/` | `/home/ubuntu` | весь домашний каталог контейнера (переживает перезапуски) |
| `volumes/exchange/` | `/exchange` | обмен файлами (виден в диалогах по пути `/exchange`) |
| `volumes/logconf/` | `/opt/1cv8/logconf` (ro) | `logcfg.xml` для ТЖ |
| `volumes/techjournal/` | `/home/ubuntu/techjournal` | файлы ТЖ, переживают контейнер |
| `volumes/client-profile/` | `/home/ubuntu/.1cv8/1C/1cv8` | профиль: списки баз, настройки |
| `volumes/licenses/` | `/home/ubuntu/.1cv8/1C/1cv8/conf` | community-лицензия |

Каталоги создаются автоматически при первом запуске. Весь каталог
`volumes/` игнорируется git.

## Подключение технологического журнала

Положить `logcfg.xml` в `volumes/logconf/`. Клиенты 1С ищут этот файл
по путям внутри контейнера; каталог `/opt/1cv8/logconf` монтируется
read-only. Точные пути подхватывания (директива `<log location=…>`)
указывайте на `/home/ubuntu/techjournal`.

## D-Bus хоста (уведомления и порталы)

В контейнер монтируется session-bus хоста
(`/run/user/<uid>/bus`), что даёт:

- уведомления из 1С на хосте (KDE-тосты);
- попытку нативных KDE-диалогов файлов: entrypoint выставляет
  `GTK_USE_PORTAL=1`, GTK-диалоги должны идти через
  `org.freedesktop.portal.FileChooser`.

Фактически платформа 1С (wxWidgets) показывает собственный GTK-диалог,
мимо портала — KDE-диалог не включается. Уведомления работают.
Подробности — ADR-0008.

## Локаль

Образ собирается с локалью `ru_RU.UTF-8`; процессы 1С запускаются с
`LC_ALL=ru_RU.UTF-8` — язык интерфейса платформы русский
(ADR-0005). Хостовая локаль в контейнер не передаётся.

## Диагностика

- Логи контейнера: `podman logs 1c-client-8.3.27.2342`
- Процессы: `bin/1c-run.sh status` или
  `podman exec 1c-client-8.3.27.2342 ps -ef`
- Отладочный образ (strace, xwininfo, mc и т.п.):
  `bin/1c-run.sh build+test`, запуск с
  `IMAGE=localhost/1c-client:8.3.27.2342-test bin/1c-run.sh …`
  (или тег `-test` в переменной `PLATFORM_VERSION`-независимо).

## Известные ограничения

- **Не задавать LD_LIBRARY_PATH** внутри контейнера — SIGSEGV толстого
  клиента (ADR-0003).
- `NO_AT_BRIDGE=1` глушит a11y-предупреждения GTK (a11y-dbus в
  контейнере отсутствует).
- Шум в логах `Failed to load module "window-decorations-gtk-module"`
  / `"colorreload-gtk-module"` — хостовые GTK-модули KDE отсутствуют в
  контейнере; на работу не влияет.
- `dconf-WARNING: failed to commit changes to dconf` — у 1С нет
  dconf-бэкенда для сохранения GTK-настроек; безвредно.
- Файловые диалоги 1С — GTK-вид (портал KDE не подключается,
  см. D-Bus выше).
- Окно конфигуратора и стартовые диалоги 1С появляются не мгновенно:
  первая отрисовка может занять 15–20 секунд после старта процесса,
  это нормально, не признак зависания.