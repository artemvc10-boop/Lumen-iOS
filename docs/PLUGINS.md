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
| `client_utils` | `send_request` (любой TL-запрос), `send_message`, `send_text`, `send_photo`, `send_document`, `send_video`, `run_on_ui_thread`, `get_user_config` |
| `org.telegram.tgnet` | `TLRPC.TL_*` (создать объект, `isinstance`), `TLObject` |
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
- Синтаксис `nonlocal` и оператор `:=` движок не выполняет; при установке об этом предупреждают.

## Отличия от exteraGram

Плагины exteraGram перехватывают методы Java-клиента Android (Xposed). На iPhone этого нет, поэтому часть таких плагинов работает лишь частично. Хуки верхнего уровня переносятся один в один: `on_send_message_hook` → так же, `on_update_hook` → так же, пункты меню → `add_menu_item`, `create_settings` → так же.

## Сырые TL-запросы и апдейты (как в exteraGram)

Подписка по имени Android-класса, точно или по подстроке, с приоритетом. Цепочка плагинов
и стратегии (`DEFAULT`, `MODIFY`, `MODIFY_FINAL`, `CANCEL`) такие же, как в exteraGram.

```python
from base_plugin import BasePlugin, HookResult, HookStrategy
from org.telegram.tgnet import TLRPC
from client_utils import send_request

class P(BasePlugin):
    def on_plugin_load(self):
        self.add_hook("TL_messages_setTyping")                  # точное имя
        self.add_hook("TL_messages_send", match_substring=True)  # все send*
        self.add_hook("TL_updateUserStatus", priority=10)

    def pre_request_hook(self, name, account, request):
        if name == "TL_messages_setTyping":
            return HookResult(strategy=HookStrategy.CANCEL)       # запрос не уйдёт
        request.silent = True                                    # true-флаги — как поля
        return HookResult(strategy=HookStrategy.MODIFY, request=request)

    def post_request_hook(self, name, account, response, error):
        return HookResult()                                      # можно подменить response/error

    def on_update_hook(self, name, account, update):
        return HookResult()                                      # CANCEL / MODIFY update

    def load(self):
        req = TLRPC.TL_messages_getHistory()
        req.peer = TLRPC.TL_inputPeerSelf()
        req.limit = 10
        send_request(req, lambda response, error: self.log(len(response.messages)))
```

Поля называются по схеме TL (`random_id`, `peer.user_id`), как на Android. `long` — обычный
`int` без потери точности. Флаги проставляются сами по наличию полей.

Ограничения iOS:
- апдейты с `pts` (новые сообщения, правки…) отменить нельзя — это порвёт последовательность
  апдейтов; их можно изменить;
- `TL_updateNewMessage` / `TL_updateNewChannelMessage` приходят через упрощённый объект
  сообщения (`update.message.text`, `dialog_id`, `chat_type`), в том числе для коротких апдейтов;
- на апдейт у плагинов 0.3 с, потом он применяется без изменений.

## Нативные экраны (только Lumen)

Плагин может открыть настоящий iOS-экран, не рисуя Android-виджеты:

```python
from lumen import ui

class P(BasePlugin):
    def open(self, context):
        self.count = 0
        ui.present(self.build)                 # build вызывается заново на каждом обновлении

    def build(self):
        return ui.screen("Мой экран", [
            ui.section(header="Раздел", rows=[
                ui.text("Нажатий: %d" % self.count, subtitle="нажми", on_click=self.bump),
                ui.switch("Флажок", value=False, on_change=lambda v: ...),
                ui.input(placeholder="Поиск", on_change=lambda v: ...),
                ui.button("Готово", style="destructive", on_click=lambda: ui.toast("ок")),
            ]),
            ui.section(rows=[ui.grid(items, columns=3, on_click=self.pick)]),
        ], search=True, bottom_button=ui.bottom_button("Отправить", on_click=self.send))

    def bump(self):
        self.count += 1          # после обработчика экран перерисуется сам
```

Строки: `ui.text`, `ui.switch`, `ui.input`, `ui.button`, `ui.selector`, `ui.chips`, `ui.image`,
`ui.grid` (сетка картинок с выбором и значками). Ещё: `ui.toast(text, "success"|"error")`,
`ui.alert(title, message, buttons=[("OK", handler)])`. Поиск: `screen(..., search=True)`,
текст приходит в `on_search` у `ui.present(build, on_search=...)`.

## Действия над приложением (только Lumen)

```python
from lumen import app
app.open_chat(user_id)               # открыть диалог (id: пользователь = id, группа/канал = -id)
app.open_chat(chat_id, message_id)   # ...с переходом к сообщению
app.open_profile(user_id)            # открыть профиль
app.open_url("tg://resolve?domain=durov")   # любая tg:// или https ссылка
where = app.current_chat()           # id чата на экране, или 0
```

Почти вся навигация уже доступна и через `app.open_url` с `tg://`-ссылками
(`tg://user?id=`, `tg://resolve?domain=`, `tg://privatepost?channel=…&post=…`). Всё, что
касается данных — отправка, правка, удаление, пересылка, реакции, прочтение, история, поиск —
делается через `send_request` (сырые TL-запросы), без изменений клиента.

## Настройки клиента (только Lumen)

```python
import lumen
lumen.settings.set("lumen.ghost.enabled", True)   # настройки Lumen — сразу
lumen.settings.set("sg.hideStories", True)         # настройки Swiftgram — при перезапуске
lumen.settings.toggle("app.forceClearGlass")       # родное стекло iOS
for key in lumen.settings.keys(): ...
```
