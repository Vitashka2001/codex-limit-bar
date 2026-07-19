<p align="center">
  <img src="Resources/AppIcon.png" width="152" alt="Codex Limit Bar icon">
</p>

<h1 align="center">Codex Limit Bar</h1>

<p align="center">
  Нативный индикатор лимитов Codex для строки меню macOS.
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-111111?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="https://github.com/Vitashka2001/codex-limit-bar/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Vitashka2001/codex-limit-bar/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/Vitashka2001/codex-limit-bar/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/Vitashka2001/codex-limit-bar"></a>
</p>

Codex Limit Bar показывает остаток доступного лимита прямо в строке меню. Приложение автоматически выбирает самое короткое доступное окно, а в раскрывающемся меню показывает подробности по 5-часовому и недельному лимитам.

## Возможности

- процент и цветная шкала в строке меню;
- подробные 5-часовой и недельный лимиты со временем сброса;
- отображение активного аккаунта и тарифного плана;
- переключение аккаунта Codex через официальный вход в браузере;
- ручное обновление и возможность приостановить мониторинг;
- запуск вместе с macOS;
- светлая и тёмная темы без дополнительных настроек.

## Требования

- macOS 13 Ventura или новее;
- установленный [Codex](https://openai.com/codex/) или официальное расширение Codex для VS Code/Cursor;
- выполненный вход в Codex.

Codex Limit Bar использует локальный `codex app-server`. Отдельный API-ключ приложению не нужен.

## Установка

1. Скачайте `Codex-Limit-Bar-1.0.0.dmg` на странице [последнего релиза](https://github.com/Vitashka2001/codex-limit-bar/releases/latest).
2. Откройте образ и перетащите **Codex Limit Bar** в `Applications`.
3. Запустите приложение. Его индикатор появится в правой части строки меню.

Первая публичная сборка подписана локальной подписью, но не нотарифицирована Apple. Если macOS заблокирует первый запуск, нажмите приложение правой кнопкой, выберите **Открыть** и подтвердите запуск. Это требуется только один раз.

## Управление

- **Мониторинг лимитов** временно останавливает фоновое обновление.
- **Сменить аккаунт Codex...** открывает официальный вход и меняет активный аккаунт Codex на этом Mac.
- **Запускать при входе** включает или отключает автозапуск.
- **Полностью выключить** завершает приложение.

Чтобы полностью отключить утилиту, сначала снимите галочку **Запускать при входе**, затем выберите **Полностью выключить**. Для повторного включения просто откройте приложение из `Applications`.

## Приватность

Приложение не читает и не сохраняет пароли, токены и API-ключи. Оно запускает установленный локально Codex и получает от него только сведения об аккаунте и лимитах. Подробности описаны в [PRIVACY.md](PRIVACY.md).

## Сборка из исходников

Понадобятся Xcode Command Line Tools и Swift 6:

```sh
swift test
./scripts/build-app.sh
```

Готовое приложение появится в `dist/Codex Limit Bar.app`.

Для создания Universal-сборки, DMG и ZIP:

```sh
./scripts/package-release.sh
```

Архивы поддерживают Apple Silicon и Intel Mac.

## Статус проекта

Это независимая open-source утилита и не официальный продукт OpenAI. Локальный протокол Codex может меняться между версиями, поэтому сообщения о несовместимости и pull request приветствуются.

Проект распространяется по лицензии [MIT](LICENSE).
