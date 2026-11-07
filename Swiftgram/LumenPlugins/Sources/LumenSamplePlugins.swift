import Foundation

// MARK: Lumen: plugins installed (disabled) on first launch, as working examples of the API.

enum LumenSamplePlugins {
    static let all: [(String, String)] = [
        ("shortcuts", shortcuts),
        ("autoreply", autoreply),
        ("message_tools", messageTools),
    ]

    static let shortcuts = #"""
    // Replaces shortcuts in messages you send: ":shrug" becomes ¯\_(ツ)_/¯ and so on.
    const SHORTCUTS = {
        ":shrug": "¯\\_(ツ)_/¯",
        ":lenny": "( ͡° ͜ʖ ͡°)",
        ":flip": "(╯°□°)╯︵ ┻━┻",
        ":unflip": "┬─┬ノ( º _ ºノ)",
        ":heart": "❤️",
    };

    Lumen.register({
        name: "Шорткаты",
        author: "Lumen",
        version: "1.0",
        description: "Заменяет :shrug, :lenny, :flip и другие на смайлики при отправке.",
        settings: [
            { type: "switch", key: "upper", title: "КАПС для сообщений, начинающихся с !", default: false },
        ],
        onSendMessage(message) {
            let text = message.text;
            for (const key in SHORTCUTS) {
                text = text.split(key).join(SHORTCUTS[key]);
            }
            if (Lumen.setting("upper") && text.startsWith("!")) {
                text = text.slice(1).toUpperCase();
            }
            return text;
        },
    });
    """#

    static let autoreply = #"""
    // Answers private messages while it is on, once per chat per hour.
    Lumen.register({
        name: "Автоответчик",
        author: "Lumen",
        version: "1.0",
        description: "Отвечает на входящие сообщения заданным текстом, не чаще раза в час на чат.",
        settings: [
            { type: "text", key: "text", title: "Текст ответа", default: "Я сейчас занят, отвечу позже." },
        ],
        onIncomingMessage(message) {
            const key = "last_" + message.peerId;
            const now = Date.now();
            const last = Lumen.storage.get(key) || 0;
            if (now - last < 60 * 60 * 1000) {
                return;
            }
            Lumen.storage.set(key, now);
            message.reply(Lumen.setting("text"));
            Lumen.log("ответил в чат " + message.peerId);
        },
    });
    """#

    static let messageTools = #"""
    // Adds actions to the message menu (long press → Lumen).
    Lumen.register({
        name: "Инструменты сообщений",
        author: "Lumen",
        version: "1.0",
        description: "Пункты в меню сообщения: длина текста, перевёрнутый текст, ответ «+».",
        menuItems: [
            {
                title: "Длина текста",
                onClick(message) {
                    const words = message.text.split(/\s+/).filter(Boolean).length;
                    Lumen.alert("Длина текста", "Символов: " + message.text.length + "\nСлов: " + words);
                },
            },
            {
                title: "Отправить задом наперёд",
                onClick(message) {
                    message.reply(Array.from(message.text).reverse().join(""));
                },
            },
            {
                title: "Ответить «+»",
                onClick(message) {
                    message.reply("+");
                },
            },
        ],
    });
    """#
}
