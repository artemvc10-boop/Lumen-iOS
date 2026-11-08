// End-to-end Meme Library flow under node, the way the iPhone drives it:
// save a chat image -> library -> select -> send; then "+" -> gallery pick -> save.
"use strict";
const fs = require("fs"), os = require("os"), path = require("path"), vm = require("vm");

const pluginFile = process.argv[2];
const root = path.resolve(__dirname, "..", "..");
const sb = fs.mkdtempSync(path.join(os.tmpdir(), "meme-"));
const docs = path.join(sb, "Documents"), plugins = path.join(sb, "plugins");
fs.mkdirSync(docs, { recursive: true });
fs.mkdirSync(path.join(plugins, "meme_library"), { recursive: true });

const PNG = Buffer.from("89504e470d0a1a0a0000000d4948445200000001000000010806000000" +
    "1f15c4890000000d4944415478da63f8ffff3f0005fe02fea7d6a1c40000000049454e44ae426082", "hex");

const log = [];
let lastPresent = null, lastUpdate = null, lastPick = null, deferred = [];
const views = {};

function mapPath(p) {
    p = String(p);
    if (p.startsWith("/storage/emulated/0")) return path.join(docs, p.slice(19));
    if (!path.isAbsolute(p)) return path.join(plugins, "meme_library", p);
    return p;
}

function fsOp(a) {
    const p = a.path === undefined ? null : mapPath(a.path);
    switch (a.action) {
        case "pluginsDir": return path.join(plugins, "meme_library");
        case "cacheDir": case "filesDir": return sb;
        case "exists": return fs.existsSync(p);
        case "isDir": return fs.existsSync(p) && fs.statSync(p).isDirectory();
        case "list": return fs.existsSync(p) ? fs.readdirSync(p) : null;
        case "mkdir": fs.mkdirSync(p, { recursive: true }); return true;
        case "remove": fs.rmSync(p, { recursive: true, force: true }); return true;
        case "move": fs.renameSync(mapPath(a.src), mapPath(a.dst)); return true;
        case "copy": fs.cpSync(mapPath(a.src), mapPath(a.dst), { recursive: true }); return true;
        case "stat": { if (!fs.existsSync(p)) return null; const s = fs.statSync(p); return { size: s.size, mtime: s.mtimeMs / 1000, isDir: s.isDirectory() }; }
        case "readText": return fs.readFileSync(p, "utf8");
        case "writeText": fs.mkdirSync(path.dirname(p), { recursive: true }); (a.append ? fs.appendFileSync : fs.writeFileSync)(p, a.text); return true;
        case "readBase64": return fs.readFileSync(p).toString("base64");
        case "writeBase64": fs.mkdirSync(path.dirname(p), { recursive: true }); (a.append ? fs.appendFileSync : fs.writeFileSync)(p, Buffer.from(a.data, "base64")); return true;
    }
    return null;
}

global.LumenNative = {
    call(op, json) {
        const a = JSON.parse(json || "null") || {};
        let r = null;
        switch (op) {
            case "fs": r = fsOp(a); break;
            case "themeColor": r = -16777216; break;
            case "imageSize": r = { width: 1, height: 1 }; break;
            case "locale": r = { language: "ru" }; break;
            case "presentView": lastPresent = a; log.push("presentView " + a.kind + (a.title ? " «" + a.title + "»" : "") + " buttons=" + (a.buttons || []).map(b => b.text).join("/")); break;
            case "updateView": lastUpdate = a; log.push("updateView #" + a.id); break;
            case "dismissView": log.push("dismissView #" + a.id); break;
            case "pickMedia": lastPick = a; log.push("pickMedia req=" + a.requestCode + " mime=" + a.mime); break;
            case "sendFile": log.push("sendFile dialog=" + a.dialogId + " " + path.basename(a.path)); break;
            case "sendMessage": log.push("sendMessage " + a.text); break;
            case "bulletin": log.push("bulletin: " + a.text); break;
            case "alert": log.push("alert «" + a.title + "» items=" + JSON.stringify(a.items)); r = 1; break;
            case "pluginError": log.push("ERROR " + a.text); break;
            case "defer": deferred.push(a.id); break;
            case "openUrl": log.push("openUrl " + a.url); break;
        }
        return JSON.stringify(r === undefined ? null : r);
    },
};

vm.runInThisContext(fs.readFileSync(path.join(root, "Telegram/Telegram-iOS/Resources/LumenPyRuntime.js"), "utf8"));
const call = (n, p) => JSON.parse(LumenHost.call(n, JSON.stringify(p)));
const drain = () => { for (let i = 0; i < 30 && deferred.length; i++) call("run_callback", { id: deferred.shift() }); };

function walk(node, fn) { if (!node) return; fn(node); (node.children || []).forEach(c => walk(c, fn)); }
function find(spec, pred) { let found = []; walk(spec, n => { if (pred(n)) found.push(n); }); return found; }

const src = fs.readFileSync(pluginFile, "utf8").replace(/\r\n/g, "\n");
const target = path.join(plugins, "meme_library.plugin");
fs.writeFileSync(target, src);
console.log("load:", call("load_plugin", { id: "meme_library", path: target, source: src, name: "Meme" }).ok);
const items = call("menu_items", { plugin: "meme_library" }).items;
const saveItem = items.find(i => i.type === "MESSAGE_CONTEXT_MENU");
const libItem = items.find(i => i.type === "CHAT_ACTION_MENU");

// 1. Save an image from a chat message.
const chatImage = path.join(sb, "chat_media.png");
fs.writeFileSync(chatImage, PNG);
call("menu_click", { plugin: "meme_library", itemId: saveItem.itemId, dialogId: 555, mediaPath: chatImage, message: { id: 7, text: "", hasMedia: true } });
drain();
const form = lastPresent;
const edits = find(form && form.view, n => n.type === "edit");
console.log("save form edits:", edits.length);
if (edits.length >= 2) {
    call("set_view_text", { vid: edits[0].vid, value: "коты" });
    call("set_view_text", { vid: edits[edits.length - 1].vid, value: "кот плачет под дождём" });
}
const saveBtn = (form && form.buttons || []).find(b => b.which === -1);
if (saveBtn) { call("run_callback", { id: saveBtn.callback }); drain(); }

// 2. Open the library (skip the tutorial) and send the meme.
const settingsPath = path.join(plugins, "meme_library", "plugin_settings.json");
fs.writeFileSync(settingsPath, JSON.stringify({ onboarding_done: true, tutorial_done: true }));
call("menu_click", { plugin: "meme_library", itemId: libItem.itemId, dialogId: 555 });
drain();
const lib = lastPresent;
const images = find(lib && lib.view, n => n.type === "image" && n.props && n.props.image);
console.log("library memes shown:", images.length);
const hasImage = n => find(n, c => c.type === "image" && c.props && c.props.image).length > 0;
const tappable = find(lib && lib.view, n => n.clickCallback && n.type === "linear" && hasImage(n));
console.log("cells:", tappable.length, "taps:", find(lib && lib.view, n => n.clickCallback).map(n => n.type + (n.text ? "«" + n.text.slice(0, 12) + "»" : "")).join(", "));
if (tappable.length) { call("run_callback", { id: tappable[0].clickCallback }); console.log("pending deferred:", deferred.length); drain(); }
const fresh = lastUpdate ? lastUpdate.view : lib.view;
// The morph FAB is the last tappable view in the tree.
const allTaps = find(fresh, n => n.clickCallback);
if (allTaps.length) { call("run_callback", { id: allTaps[allTaps.length - 1].clickCallback }); drain(); }

// 3. "+" -> gallery pick -> save form.
lastPick = null;
call("menu_click", { plugin: "meme_library", itemId: libItem.itemId, dialogId: 555 });
drain();
const lib2 = lastPresent;
const taps2 = find(lib2 && lib2.view, n => n.clickCallback);
if (taps2.length) { call("run_callback", { id: taps2[taps2.length - 1].clickCallback }); drain(); }
if (lastPick) {
    const picked = path.join(sb, "picked.png");
    fs.writeFileSync(picked, PNG);
    call("activity_result", { requestCode: lastPick.requestCode, path: picked, mime: "image/png" });
    drain();
}

console.log(log.join("\n"));
const db = path.join(plugins, "meme_library", "memes_db.json");
if (fs.existsSync(db)) {
    const memes = JSON.parse(fs.readFileSync(db, "utf8")).memes || [];
    console.log("memes in db:", memes.length, memes.map(m => (m.category || "") + ": " + m.tags).join(" | "));
}
fs.rmSync(sb, { recursive: true, force: true });
