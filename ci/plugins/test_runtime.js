// Runs the bundled plugin runtime under node with a stand-in for the app's LumenNative bridge,
// loads every .plugin given on the command line and exercises it like the app would.
//
//   node ci/plugins/test_runtime.js path/to/a.plugin [more.plugin ...]
//
// Fails (exit 1) when a plugin cannot be loaded or the host reports an error.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..", "..");
const bundle = fs.readFileSync(path.join(root, "Telegram", "Telegram-iOS", "Resources", "LumenPyRuntime.js"), "utf8");

const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "lumen-plugins-"));
const pluginsDir = path.join(sandbox, "plugins");
const documentsDir = path.join(sandbox, "Documents");
fs.mkdirSync(pluginsDir, { recursive: true });
fs.mkdirSync(documentsDir, { recursive: true });

const events = [];
const settings = {};
const menus = {};
const deferred = [];
let failures = 0;

function mapPath(p) {
    p = String(p);
    if (p.startsWith("/storage/emulated/0")) {
        return path.join(documentsDir, p.slice("/storage/emulated/0".length));
    }
    if (p.startsWith("/sdcard")) {
        return path.join(documentsDir, p.slice("/sdcard".length));
    }
    if (!path.isAbsolute(p)) {
        return path.join(pluginsDir, p);
    }
    return p;
}

function fsOp(a) {
    const p = a.path === undefined ? null : mapPath(a.path);
    switch (a.action) {
        case "pluginsDir": return pluginsDir;
        case "cacheDir": return path.join(sandbox, "cache");
        case "filesDir": return path.join(sandbox, "files");
        case "exists": return fs.existsSync(p);
        case "isDir": return fs.existsSync(p) && fs.statSync(p).isDirectory();
        case "list": return fs.existsSync(p) ? fs.readdirSync(p) : null;
        case "mkdir": fs.mkdirSync(p, { recursive: !!a.parents }); return true;
        case "remove": fs.rmSync(p, { recursive: true, force: true }); return true;
        case "move": fs.renameSync(mapPath(a.src), mapPath(a.dst)); return true;
        case "copy": fs.cpSync(mapPath(a.src), mapPath(a.dst), { recursive: true }); return true;
        case "stat": {
            if (!fs.existsSync(p)) return null;
            const s = fs.statSync(p);
            return { size: s.size, mtime: s.mtimeMs / 1000, isDir: s.isDirectory() };
        }
        case "readText": return fs.readFileSync(p, "utf8");
        case "writeText": (a.append ? fs.appendFileSync : fs.writeFileSync)(p, a.text, "utf8"); return true;
        case "readBase64": return fs.readFileSync(p).toString("base64");
        case "writeBase64": (a.append ? fs.appendFileSync : fs.writeFileSync)(p, Buffer.from(a.data, "base64")); return true;
        default: throw new Error("fs action " + a.action);
    }
}

const zips = {};

global.LumenNative = {
    call(op, json) {
        const a = JSON.parse(json || "null") || {};
        let result = null;
        switch (op) {
            case "print": case "log": events.push(["log", a.plugin, a.text !== undefined ? a.text : a]); break;
            case "pluginError": events.push(["error", a.plugin, a.text]); break;
            case "getSetting": result = (settings[a.plugin] || {})[a.key]; if (result === undefined) result = null; break;
            case "setSetting": (settings[a.plugin] = settings[a.plugin] || {})[a.key] = a.value; break;
            case "getAllSettings": result = settings[a.plugin] || {}; break;
            case "menuChanged": menus[a.plugin] = a.items; break;
            case "bulletin": events.push(["bulletin", a.plugin, a.text]); break;
            case "alert": events.push(["alert", a.plugin, a.title, a.buttons.map(b => b.text)]); result = 1; break;
            case "dismissAlert": break;
            case "defer": deferred.push(a.id); break;
            case "fs": result = fsOp(a); break;
            case "zip": {
                // Enough for the tests: archives are kept in memory as name -> base64.
                const key = mapPath(a.path);
                if (a.action === "create") {
                    const entries = {};
                    for (const e of a.entries) entries[e.name] = e.data !== undefined ? e.data : fs.readFileSync(mapPath(e.path)).toString("base64");
                    zips[key] = entries; fs.writeFileSync(key, "PK-mock");
                    result = true;
                } else if (a.action === "list") {
                    result = zips[key] ? Object.keys(zips[key]) : null;
                } else if (a.action === "read") {
                    result = zips[key] ? zips[key][a.name] : null;
                } else if (a.action === "extract") {
                    for (const name of Object.keys(zips[key] || {})) {
                        const target = path.join(mapPath(a.dst), name);
                        fs.mkdirSync(path.dirname(target), { recursive: true });
                        fs.writeFileSync(target, Buffer.from(zips[key][name], "base64"));
                    }
                    result = true;
                }
                break;
            }
            case "sleep": break;
            case "localtime": {
                const d = new Date((a.t || 0) * 1000);
                result = [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes(), d.getSeconds(), (d.getDay() + 6) % 7, 1, 0];
                break;
            }
            case "mktime": result = new Date(a.parts[0], a.parts[1] - 1, a.parts[2], a.parts[3], a.parts[4], a.parts[5]).getTime() / 1000; break;
            case "strftime": {
                const d = new Date((a.t || 0) * 1000);
                const pad = n => String(n).padStart(2, "0");
                result = a.format.replace(/%Y/g, d.getFullYear()).replace(/%m/g, pad(d.getMonth() + 1)).replace(/%d/g, pad(d.getDate()))
                    .replace(/%H/g, pad(d.getHours())).replace(/%M/g, pad(d.getMinutes())).replace(/%S/g, pad(d.getSeconds()));
                break;
            }
            case "http": result = { status: 200, body: Buffer.from("{}").toString("base64"), headers: {} }; break;
            case "sendMessage": events.push(["sendMessage", a.plugin, a.dialogId, a.text]); break;
            case "sendFile": events.push(["sendFile", a.plugin, a.dialogId, a.path]); break;
            case "clipboard": events.push(["clipboard", a.plugin, a.text]); break;
            case "accountInfo": result = { userId: 777, firstName: "Test" }; break;
            case "hash": result = require("crypto").createHash(a.algorithm).update(Buffer.from(a.data, "base64")).digest("hex"); break;
            case "uuid": result = require("crypto").randomUUID(); break;
            default: events.push(["unknown-op", a.plugin, op]);
        }
        return JSON.stringify(result === undefined ? null : result);
    },
};

vm.runInThisContext(bundle, { filename: "LumenPyRuntime.js" });
const host = global.LumenHost;

function call(name, payload) {
    const raw = host.call(name, JSON.stringify(payload));
    const result = JSON.parse(raw);
    if (result && result.error) {
        console.log("  ✗ " + name + ": " + result.error);
        failures++;
    }
    return result;
}

function drainDeferred() {
    for (let i = 0; i < 20 && deferred.length > 0; i++) {
        const id = deferred.shift();
        call("run_callback", { id: id });
    }
}

function metadata(source) {
    const meta = {};
    const re = /^__(\w+)__\s*=\s*(["'])(.*?)\2/gm;
    let m;
    while ((m = re.exec(source)) !== null) meta[m[1]] = m[3];
    return meta;
}

for (const file of process.argv.slice(2)) {
    const source = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
    const meta = metadata(source);
    const id = meta.id || path.basename(file, ".plugin");
    const target = path.join(pluginsDir, id + ".plugin");
    fs.writeFileSync(target, source);
    console.log("● " + path.basename(file) + " (" + id + ")");
    const before = failures;
    const eventsBefore = events.length;
    const loaded = call("load_plugin", { id: id, path: target, source: source, name: meta.name || id });
    if (!loaded || loaded.error) {
        continue;
    }
    drainDeferred();
    const page = call("create_settings", { plugin: id });
    const items = (page && page.items) || [];
    console.log("  settings: " + items.map(i => i.type + (i.text ? "«" + String(i.text).slice(0, 24) + "»" : "")).join(", "));
    for (const item of items) {
        if (item.hasSubpage) call("settings_sub", { plugin: id, handle: item.handle });
    }
    const sent = call("send_hook", { dialogId: 12345, text: "hello :shrug" });
    console.log("  send hook → " + JSON.stringify(sent));
    call("update_hook", { id: 5, dialogId: 12345, authorId: 12345, text: "входящее", out: false, date: 1, chatType: "private" });
    drainDeferred();
    const menu = menus[id] || [];
    console.log("  menu: " + menu.map(m => m.type + "«" + m.text + "»").join(", "));
    for (const item of menu) {
        call("menu_click", { plugin: id, itemId: item.itemId, dialogId: 12345, message: { id: 5, text: "тестовое сообщение", out: false, date: 1 } });
        drainDeferred();
    }
    call("app_event", { event: "PAUSE" });
    call("unload_plugin", { id: id });
    const own = events.slice(eventsBefore).filter(e => e[1] === id);
    const errors = own.filter(e => e[0] === "error");
    for (const e of errors) console.log("  ✗ " + e[2]);
    failures += errors.length;
    for (const e of own.filter(e => e[0] !== "error").slice(0, 8)) console.log("  · " + e.slice(0, 1).concat(e.slice(2)).map(x => JSON.stringify(x)).join(" ").slice(0, 160));
    console.log(failures === before ? "  ✓ ok" : "  ✗ failed");
}

fs.rmSync(sandbox, { recursive: true, force: true });
console.log(failures === 0 ? "\nALL OK" : "\nFAILURES: " + failures);
process.exit(failures === 0 ? 0 : 1);
