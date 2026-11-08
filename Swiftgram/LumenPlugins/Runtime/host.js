// Lumen plugin host: runs exteraGram-style .plugin files (Python) on Skulpt inside one
// JavaScriptCore context. Swift calls LumenHost.call(name, json) on its plugin queue; Python
// reaches the app through LumenNative.call(op, json) (a synchronous Swift block).
//
// Everything Swift and Python exchange is a JSON string, so neither side deals with the
// other's object model.

var LumenHost = (function () {
    "use strict";

    // Top-level packages that only exist on Android. Importing them yields stub modules, so
    // plugins load and their Android-only parts quietly do nothing.
    var STUB_PACKAGES = ["android", "androidx", "org", "com", "kotlin", "kotlinx", "dalvik", "javax",
        "extera_utils", "elyxcore", "log_utils", "intents", "dev_server", "PIL", "bs4", "lxml", "yaml",
        "debugpy", "chaquopy"];

    var files = Sk.builtinFiles.files;
    // Module paths plugins import from (filled by _lumen_java.scan_imports).
    var knownPackages = {};
    var hostModule = null;

    function isStubPath(path) {
        // path looks like "src/lib/android/widget/__init__.py"
        var match = /^src\/lib\/([A-Za-z0-9_]+)((?:\/[A-Za-z0-9_$]+)*)\/__init__\.py$/.exec(path);
        if (!match) {
            return null;
        }
        var top = match[1];
        var rest = match[2];
        // Our own modules imported from inside a stub package are looked up relative to it
        // first; those lookups must miss so the absolute import is used.
        if (rest.indexOf("/_lumen") >= 0) {
            return null;
        }
        // Java packages are lower case; a capitalised last part is a class, which the
        // package's stub module provides as an attribute.
        var dotted = (top + rest).replace(/\//g, ".");
        var last = dotted.split(".").pop();
        if (rest.length > 0 && /^[A-Z]/.test(last) && !knownPackages[dotted]) {
            return null;
        }
        if (STUB_PACKAGES.indexOf(top) >= 0 || (top === "java" && rest.length > 0)) {
            return (top + rest).replace(/\//g, ".");
        }
        return null;
    }

    function read(path) {
        if (files[path] !== undefined) {
            return files[path];
        }
        var stubName = isStubPath(path);
        if (stubName !== null) {
            return "import _lumen_java\n_lumen_java.fill_module(" + JSON.stringify(stubName) + ")\n";
        }
        throw "File not found: '" + path + "'";
    }

    var nativeModuleSource = "var $builtinmodule = function (name) {\n" +
        "  var mod = {};\n" +
        "  mod.native_call = new Sk.builtin.func(function (op, arg) {\n" +
        "    var result = LumenNative.call(Sk.ffi.remapToJs(op), Sk.ffi.remapToJs(arg));\n" +
        "    return new Sk.builtin.str(result === undefined || result === null ? 'null' : String(result));\n" +
        "  });\n" +
        "  mod.load_module = new Sk.builtin.func(function (name, source) {\n" +
        "    var n = Sk.ffi.remapToJs(name);\n" +
        "    return Sk.importModuleInternal_(n, false, n, Sk.ffi.remapToJs(source), undefined, false, false);\n" +
        "  });\n" +
        "  mod.forget_module = new Sk.builtin.func(function (name) {\n" +
        "    var n = Sk.ffi.remapToJs(name);\n" +
        "    try { Sk.abstr.objectDelItem(Sk.sysmodules, new Sk.builtin.str(n)); } catch (e) {}\n" +
        "    return Sk.builtin.none.none$;\n" +
        "  });\n" +
        "  mod.now_ms = new Sk.builtin.func(function () { return new Sk.builtin.float_(Date.now()); });\n" +
        "  mod.b64encode = new Sk.builtin.func(function (data) { return new Sk.builtin.str(LumenHost.b64encode(data.v)); });\n" +
        "  mod.b64decode = new Sk.builtin.func(function (text) { return new Sk.builtin.bytes(LumenHost.b64decode(Sk.ffi.remapToJs(text))); });\n" +
        "  mod.register_package = new Sk.builtin.func(function (name) { LumenHost.registerPackage(Sk.ffi.remapToJs(name)); return Sk.builtin.none.none$; });\n" +
        "  mod.set_file = new Sk.builtin.func(function (path) { Sk.builtins.__file__ = path; return Sk.builtin.none.none$; });\n" +
        "  mod.install_open = new Sk.builtin.func(function (fn) { Sk.builtins.open = fn; return Sk.builtin.none.none$; });\n" +
        "  return mod;\n" +
        "};\n";

    var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var B64_INDEX = (function () {
        var table = {};
        for (var i = 0; i < B64.length; i++) {
            table[B64.charAt(i)] = i;
        }
        return table;
    })();

    function b64encode(bytes) {
        var out = [];
        var i = 0;
        for (; i + 2 < bytes.length; i += 3) {
            var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
            out.push(B64.charAt((n >> 18) & 63), B64.charAt((n >> 12) & 63), B64.charAt((n >> 6) & 63), B64.charAt(n & 63));
        }
        if (i < bytes.length) {
            var rest = bytes.length - i;
            var m = bytes[i] << 16 | (rest > 1 ? bytes[i + 1] << 8 : 0);
            out.push(B64.charAt((m >> 18) & 63), B64.charAt((m >> 12) & 63), rest > 1 ? B64.charAt((m >> 6) & 63) : "=", "=");
        }
        return out.join("");
    }

    function b64decode(text) {
        var clean = String(text || "").replace(/[^A-Za-z0-9+/]/g, "");
        var length = Math.floor(clean.length * 3 / 4);
        var bytes = new Uint8Array(length);
        var j = 0;
        for (var i = 0; i < clean.length; i += 4) {
            var a = B64_INDEX[clean.charAt(i)] || 0;
            var b = B64_INDEX[clean.charAt(i + 1)] || 0;
            var c = B64_INDEX[clean.charAt(i + 2)];
            var d = B64_INDEX[clean.charAt(i + 3)];
            var n = (a << 18) | (b << 12) | ((c || 0) << 6) | (d || 0);
            if (j < length) { bytes[j++] = (n >> 16) & 255; }
            if (c !== undefined && j < length) { bytes[j++] = (n >> 8) & 255; }
            if (d !== undefined && j < length) { bytes[j++] = n & 255; }
        }
        return bytes.subarray(0, j);
    }

    function setup() {
        files["src/lib/_lumen.js"] = nativeModuleSource;
        Sk.configure({
            __future__: Sk.python3,
            read: read,
            output: function (text) {
                if (String(text).trim().length > 0) {
                    LumenNative.call("print", JSON.stringify(String(text)));
                }
            },
            execLimit: 15000,
        });
        Sk.execStart = Date.now();
        hostModule = Sk.importModuleInternal_("_lumen_host", false, "_lumen_host", undefined, undefined, false, false);
    }

    function formatError(error) {
        try {
            if (error instanceof Sk.builtin.BaseException) {
                var text = error.toString();
                if (error.traceback && error.traceback.length > 0) {
                    var frame = error.traceback[0];
                    text += " (" + frame.filename + ":" + frame.lineno + ")";
                }
                return text;
            }
            return String(error);
        } catch (e) {
            return "unknown error";
        }
    }

    // Calls _lumen_host.<name>(json) and returns its JSON string result.
    function call(name, json) {
        try {
            if (hostModule === null) {
                setup();
            }
            var fn = hostModule.tp$getattr(new Sk.builtin.str(name));
            if (fn === undefined) {
                return JSON.stringify({ error: "no host function " + name });
            }
            Sk.execStart = Date.now();
            var result = Sk.misceval.callsimArray(fn, [new Sk.builtin.str(json || "null")]);
            return Sk.ffi.remapToJs(result);
        } catch (error) {
            return JSON.stringify({ error: formatError(error) });
        }
    }

    function registerPackage(name) {
        var parts = String(name).split(".");
        for (var i = 1; i <= parts.length; i++) {
            knownPackages[parts.slice(0, i).join(".")] = true;
        }
    }

    return { call: call, b64encode: b64encode, b64decode: b64decode, registerPackage: registerPackage };
})();
