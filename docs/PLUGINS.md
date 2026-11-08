# Плагины Lumen

Плагин — это один файл **`.plugin`** на Python, как в exteraGram. Установка: нажми на файл `.plugin` в любом чате → **«Установить плагин»**, либо **Настройки → Lumen → 🧩 Плагины → Установить из файла**.

Каждый плагин работает в изолированном интерпретаторе (Skulpt, Python 3). Ошибка в плагине видна в его карточке и в журнале; приложение она не роняет.

> **Важно.** Плагины видят твои сообщения и то, что ты отправляешь, могут читать файлы и выходить в сеть. Ставь только те, которым доверяешь. Установка из непроверенного источника (любой файл не из каталога Lumen) требует включить тумблер «Непроверенные источники» и подтвердить предупреждение — вся ответственность на тебе.

## Пример

```python
__id__ = "my_plugin"
__name__ = "Мой плагин"
__description__ = "Что он делает"
__author__ = "я"
__version__ = "1.0"
__min_version__ = "11.12.0"

from base_plugin import BasePlugin, MenuItemData, MenuItemType, HookResult, HookStrategy
from client_utils import send_message
from ui.settings import Header, Switch, Input, Divider
from ui.bulletin import BulletinHelper


class MyPlugin(BasePlugin):
    def on_plugin_load(self):
        self.add_on_send_message_hook()          # ловить отправку
        self.add_hook("TL_updateNewMessage")      # ловить входящие
        self.add_menu_item(MenuItemData(
            menu_type=MenuItemType.MESSAGE_CONTEXT_MENU,
            text="Моё действие",
            on_click=self.on_action,
        ))

    def create_settings(self):
        return [
            Header(text="Настройки"),
            Switch(key="loud", text="Капсом", default=False),
            Input(key="suffix", text="Приписка", default=""),
            Divider(text="Пояснение внизу секции"),
        ]

    # Перед отправкой каждого сообщения.
    def on_send_message_hook(self, account, params):
        text = params.message or ""
        if self.get_setting("loud", False):
            params.message = text.upper()
            return HookResult(strategy=HookStrategy.MODIFY, params=params)
        return HookResult()                        # без изменений; CANCEL — отменить

    # На каждое входящее сообщение.
    def on_update_hook(self, name, account, update):
        msg = update.message
        if not msg.out and msg.chat_type == "private":
            send_message({"peer": msg.dialog_id, "message": "автоответ"})

    # Пункт меню сообщения (долгое нажатие → пункт плагина).
    def on_action(self, context):
        msg = context.get("message")
        BulletinHelper.show_success("Длина: " + str(len(msg.messageOwner.message)))
```

## Что поддерживается

| Модуль | Что есть |
|---|---|
| `base_plugin` | `BasePlugin` (get/set_setting, log, add_menu_item, add_on_send_message_hook, add_hook), `MenuItemData`, `MenuItemType`, `HookResult`, `HookStrategy`, `AppEvent` |
| `client_utils` | `send_message`, `send_text`, `send_photo`, `send_document`, `send_video`, `run_on_ui_thread`, `get_user_config` |
| `ui.settings` | `Header`, `Divider`, `Switch`, `Input`, `EditText`, `Selector`, `Text` |
| `ui.bulletin` | `BulletinHelper.show_info/show_error/show_success/...` |
| `ui.alert` | `AlertDialogBuilder` (нативное окно с кнопками и списком) |
| `android_utils` | `copy_to_clipboard`, `run_on_ui_thread`, `OnClickListener` |
| `markdown_utils` | `parse_markdown` |
| `file_utils` | директории, чтение/запись файлов |
| стандартная библиотека | `os`, `os.path`, `json`, `time`, `re`, `math`, `random`, `base64`, `hashlib`, `uuid`, `shutil`, `zipfile`, `io`, `contextlib`, `typing`, `dataclasses`, `threading`, `requests`, `urllib.parse`, `urllib.request` |

`dialog_id` и `peer` — как в Android: пользователь = его id, группа/канал = минус id.

Файлы плагина лежат в его собственной папке; пути вида `/storage/emulated/0/...` отображаются в папку «Документы» приложения.

## Чего нет (и не будет на iPhone)

- **Перехват Java-методов** (`hook_method`, `hook_all_methods`, `find_class`, Xposed) — на iOS нет Java. Такие вызовы не падают, но ничего не делают, и плагин об этом пишет в журнал. Например, iOS Liquid Glass загрузится, но работать не будет: iOS 26 рисует «стекло» сама.
- **Android View и ресурсы** (`LinearLayout`, `BitmapFactory`, `R.drawable.*` и т. п.) — это заглушки. Плагины со своим сложным UI на Android-виджетах покажут пустоту; их логику нужно переписывать на `create_settings`, меню и `AlertDialogBuilder`.
- **`pre_request_hook` / `post_request_hook`** (сырые TL-запросы) — не поддерживаются.
- Синтаксис `nonlocal` и оператор `:=` движок не выполняет; при установке об этом предупреждают.

## Отличия от exteraGram

Плагины exteraGram перехватывают методы Java-клиента Android (Xposed). На iPhone этого нет, поэтому часть таких плагинов работает лишь частично. Хуки верхнего уровня переносятся один в один: `on_send_message_hook` → так же, `on_update_hook` → так же, пункты меню → `add_menu_item`, `create_settings` → так же.
