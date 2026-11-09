// TL hooks under node: pre/post request, update, send_request and TLRPC objects, driven the
// way LumenPluginManager+TLHooks.swift does (JSON in the LumenTLJSON shape).
"use strict";
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.resolve(__dirname, "..", "..");

const log = [];
let interest = null, lastRequest = null;
global.LumenNative = {
    call(op, json) {
        const a = JSON.parse(json || "null") || {};
        switch (op) {
            case "setTLHooks": interest = a; break;
            case "tlRequest": lastRequest = a; break;
            case "pluginError": log.push("ERROR " + a.text); break;
            case "print": case "log": log.push("log " + (a.text || a)); break;
        }
        return "null";
    }
};
vm.runInThisContext(fs.readFileSync(path.join(root, "Telegram/Telegram-iOS/Resources/LumenPyRuntime.js"), "utf8"));
const call = (n, p) => JSON.parse(LumenHost.call(n, JSON.stringify(p)));

const source = `
__id__ = "tl_test"
__name__ = "TL test"
from base_plugin import BasePlugin, HookResult, HookStrategy
from org.telegram.tgnet import TLRPC
from client_utils import send_request

class P(BasePlugin):
    def on_plugin_load(self):
        self.add_hook("TL_messages_setTyping")
        self.add_hook("TL_messages_sendMessage", priority=5)
        self.add_hook("TL_updateUserStatus")
        self.add_hook("TL_messages_getHistory")
        self.got = None

    def pre_request_hook(self, name, account, request):
        if name == "TL_messages_setTyping":
            return HookResult(strategy=HookStrategy.CANCEL)
        if name == "TL_messages_sendMessage":
            assert isinstance(request, TLRPC.TL_messages_sendMessage), "isinstance"
            assert request.getClass().getSimpleName() == "TL_messages_sendMessage"
            assert request.random_id == 9007199254740993, "int64 precision %r" % request.random_id
            assert request.silent == False
            request.message = request.message.upper()
            request.silent = True
            return HookResult(strategy=HookStrategy.MODIFY, request=request)
        return HookResult()

    def post_request_hook(self, name, account, response, error):
        if name == "TL_messages_getHistory" and error is not None:
            r = TLRPC.TL_messages_messages()
            r.messages = []
            r.chats = []
            r.users = []
            return HookResult(strategy=HookStrategy.MODIFY, response=r)
        return HookResult()

    def on_update_hook(self, name, account, update):
        if update.status.getClass().getSimpleName() == "TL_userStatusOnline":
            return HookResult(strategy=HookStrategy.CANCEL)
        return HookResult()

    def ask(self):
        req = TLRPC.TL_messages_getHistory()
        req.peer = TLRPC.TL_inputPeerSelf()
        req.limit = 3
        send_request(req, lambda resp, err: self.done(resp, err))

    def done(self, resp, err):
        self.got = (len(resp.messages), err)
        self.log("got %d" % len(resp.messages))
`;
const load = call("load_plugin", { id: "tl_test", source, name: "TL test" });
console.log("load:", JSON.stringify(load));
console.log("interest:", JSON.stringify(interest));

const results = [];
const check = (label, got, want) => { const ok = JSON.stringify(got) === JSON.stringify(want); results.push(ok); console.log((ok ? "OK  " : "FAIL") + " " + label + (ok ? "" : " got=" + JSON.stringify(got))); };

let r = call("tl_hook", { kind: "pre", name: "TL_messages_setTyping", account: 1, data: JSON.stringify({ _: "messages.setTyping", flags: 0, peer: { _: "inputPeerSelf" }, action: { _: "sendMessageTypingAction" } }) });
check("setTyping cancelled", r.decision, "cancel");

r = call("tl_hook", { kind: "pre", name: "TL_messages_sendMessage", account: 1, data: JSON.stringify({ _: "messages.sendMessage", flags: 0, peer: { _: "inputPeerSelf" }, message: "hi", random_id: { "#l": "9007199254740993" } }) });
check("sendMessage modified", [r.decision, r.data && r.data.message, r.data && r.data.flags, r.data && r.data.random_id], ["replace", "HI", 32, { "#l": "9007199254740993" }]);

r = call("tl_hook", { kind: "post", name: "TL_messages_getHistory", account: 1, errorCode: 400, errorText: "PEER_ID_INVALID" });
check("error turned into response", [r.decision, r.data && r.data._], ["replace", "messages.messages"]);

r = call("tl_hook", { kind: "update", name: "TL_updateUserStatus", account: 1, data: JSON.stringify({ _: "updateUserStatus", user_id: { "#l": "42" }, status: { _: "userStatusOnline", expires: 5 } }) });
check("online status dropped", r.decision, "cancel");
r = call("tl_hook", { kind: "update", name: "TL_updateUserStatus", account: 1, data: JSON.stringify({ _: "updateUserStatus", user_id: { "#l": "42" }, status: { _: "userStatusOffline", was_online: 5 } }) });
check("offline status kept", r.decision, "keep");

r = call("tl_hook", { kind: "pre", name: "TL_help_getConfig", account: 1, data: JSON.stringify({ _: "help.getConfig" }) });
check("unhooked name kept", r.decision, "keep");

// send_request round trip: the plugin asks, the app answers through run_callback.
LumenHost.call("run_deferred_test", "null");
const runPy = (code) => call("load_plugin", { id: "runner" + Math.random(), source: "from base_plugin import BasePlugin\nclass R(BasePlugin):\n    def on_plugin_load(self):\n" + code, name: "r" });
runPy("        import _lumen_host\n        _lumen_host._plugins['tl_test']['instance'].ask()\n");
check("request JSON", lastRequest && [lastRequest.request._, lastRequest.request.limit, lastRequest.request.peer._], ["messages.getHistory", 3, "inputPeerSelf"]);
call("run_callback", { id: lastRequest.callback, args: [{ _: "messages.messages", messages: [{ _: "messageEmpty", id: 1 }], chats: [], users: [] }, null] });
check("callback delivered", log.filter(l => l.indexOf("got 1") >= 0).length, 1);

call("unload_plugin", { id: "tl_test" });
check("interest cleared on unload", interest && interest.exact.filter(n => n.indexOf("messages") >= 0).length, 0);

const errors = log.filter(l => l.startsWith("ERROR"));
if (errors.length) console.log(errors.join("\n"));
const failed = results.filter(x => !x).length + errors.length;
console.log(failed ? failed + " FAILED" : "all passed");
process.exit(failed ? 1 : 0);
