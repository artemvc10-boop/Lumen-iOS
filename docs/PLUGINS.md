# Плагины Lumen

Плагин — это один файл `.js`. Установка: **Настройки → Lumen → 🧩 Плагины → Установить из файла**.
Каждый плагин работает в своём изолированном JavaScript-контексте (JavaScriptCore). Ошибка в плагине видна в его карточке и в журнале, приложение она не роняет.

## Регистрация

```js
Lumen.register({
    name: "Мой плагин",
    author: "я",
    version: "1.0",
    description: "Что он делает",

    settings: [
        { type: "switch", key: "enabled", title: "Включить фишку", default: true },
        { type: "text", key: "greeting", title: "Текст приветствия", default: "Привет!" },
    ],

    onLoad() {},                 // плагин включили
    onUnload() {},               // плагин выключили или удалили
    onSettingChanged(key, value) {},

    // Перед отправкой каждого сообщения. Вернуть строку — отправится она;
    // вернуть false — сообщение не отправится; ничего не вернуть — без изменений.
    onSendMessage(message) {     // message: { text, peerId }
        return message.text;
    },

    // На каждое входящее сообщение.
    onIncomingMessage(message) { // { text, peerId, messageId, authorId, chatType, reply(text) }
                                 // chatType: "private", "group", "channel", "secret"
    },

    // Пункты меню сообщения (долгое нажатие → Lumen).
    menuItems: [
        { title: "Скопировать капсом", onClick(message) { message.reply(message.text.toUpperCase()); } },
    ],
});
```

## API

| | |
|---|---|
| `Lumen.setting(key)` | значение настройки плагина |
| `Lumen.storage.get(key)` / `Lumen.storage.set(key, value)` | постоянное хранилище плагина (строки, числа, true/false) |
| `Lumen.sendMessage(peerId, text)` | отправить сообщение в чат (из того аккаунта, где сработал хук) |
| `message.reply(text)` | ответить в чат этого сообщения |
| `Lumen.fetch(url, { method, body, headers }, (error, body, status) => {})` | HTTP-запрос |
| `Lumen.alert(title, text)` | показать окно |
| `Lumen.log(...)`, `console.log(...)` | запись в журнал плагинов |

`peerId`, `authorId` — строки: 64-битные id Telegram не помещаются в числа JavaScript без потерь.

## Отличия от плагинов exteraGram

Плагины exteraGram написаны на Python и перехватывают Java-методы Android-клиента (Xposed). На iPhone нет ни Java, ни подмены методов Swift, поэтому они не переносятся напрямую. Логику обычно легко переписать на хуки выше: `on_send_message_hook` → `onSendMessage`, `on_update_hook` → `onIncomingMessage`, пункты меню → `menuItems`, `create_settings` → `settings`.
