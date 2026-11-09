// Profile/chat decorations (lumen.profile) under node: a plugin sets a decoration, listens
// for profile-open and chat-user events, and the app reads what it stored.
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.resolve(__dirname, "..", "..");

const store = {};           // userId -> spec, as LumenDecorations keeps it
const log = [];
global.LumenNative = {
    call(op, json) {
        const a = JSON.parse(json || "null") || {};
        switch (op) {
            case "decorationSet": store[a.userId] = a.spec; break;
            case "decorationClear": if (a.all) { for (const k of Object.keys(store)) delete store[k]; } else { delete store[a.userId]; } break;
            case "pluginError": log.push("ERR " + a.text); break;
            case "print": case "log": log.push("log " + (a.text || a)); break;
        }
        return "null";
    }
};
vm.runInThisContext(fs.readFileSync(path.join(root, "Telegram/Telegram-iOS/Resources/LumenPyRuntime.js"), "utf8"));
const call = (n, p) => JSON.parse(LumenHost.call(n, JSON.stringify(p)));

const source = `
__id__ = "decor_test"
__name__ = "Decor test"
from base_plugin import BasePlugin
from lumen import profile

class P(BasePlugin):
    def on_plugin_load(self):
        self.opened = []
        self.seen = []
        profile.set(777, {
            "banner": {"type": "gradient", "colors": ["#FF5E62", "#FF9966"], "angle": 90},
            "avatar": {"shape": 6},
            "name": {"color": "#FFD700"},
            "chat": {"nameColor": "#FFD700", "tag": {"text": "[X]"}},
        })

    def on_profile_open(self, user_id):
        self.opened.append(user_id)
        if user_id == 123:
            profile.set(123, {"name": {"color": "#00FF00"}})

    def on_chat_users(self, user_ids):
        self.seen.extend(user_ids)
`;
const results = [];
const check = (label, got, want) => { const ok = JSON.stringify(got) === JSON.stringify(want); results.push(ok); console.log((ok ? "OK  " : "FAIL") + " " + label + (ok ? "" : " got=" + JSON.stringify(got))); };

console.log("load:", JSON.stringify(call("load_plugin", { id: "decor_test", source, name: "Decor" })));
check("set on load", store[777] && [store[777].banner.type, store[777].avatar.shape, store[777].chat.tag.text], ["gradient", 6, "[X]"]);

call("decor_event", { kind: "profile", userId: 123 });
check("profile event -> lazy set", store[123] && store[123].name.color, "#00FF00");
call("decor_event", { kind: "chat", userIds: [10, 20, 30] });

const probe = call("load_plugin", { id: "probe", source: "from base_plugin import BasePlugin\nimport _lumen_host\nclass R(BasePlugin):\n    def on_plugin_load(self):\n        inst = _lumen_host._plugins['decor_test']['instance']\n        self.log('opened=%r seen=%r' % (inst.opened, inst.seen))\n", name: "probe" });
check("events delivered", log.filter(l => l.indexOf("opened=[123] seen=[10, 20, 30]") >= 0).length, 1);

const errors = log.filter(l => l.startsWith("ERR"));
if (errors.length) console.log(errors.join("\n"));
const failed = results.filter(x => !x).length + errors.length;
console.log(failed ? failed + " FAILED" : "all passed");
process.exit(failed ? 1 : 0);
