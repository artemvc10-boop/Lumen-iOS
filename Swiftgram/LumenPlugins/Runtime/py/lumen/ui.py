# Native screens for plugins. A plugin describes a screen declaratively and Lumen renders it
# as a real iOS screen (lists, grids, forms, search), then reports taps, edits and selections
# back. This replaces drawing Android views by hand, so a full plugin UI needs no app rebuild.
#
#   from lumen import ui
#
#   def build():
#       rows = [ui.text("Привет", subtitle="строка", on_click=lambda: ui.toast("tap"))]
#       return ui.screen("Мой экран", [ui.section(rows=rows)])
#
#   ui.present(build)      # push the screen; build() is called again on every refresh
#
# Rows/sections are plain dicts; the helpers below just fill them in. Callbacks are stored by
# id on the Python side and fired when the native side sends an event.
from _lumen_bridge import native

_screens = {}
_counter = [0]


def _next_id():
    _counter[0] += 1
    return "w%d" % _counter[0]


# MARK: Row and section builders

def _row(kind, **kwargs):
    row = {"type": kind}
    explicit = kwargs.pop("id", None)
    if explicit is not None:
        row["id"] = explicit
    row.update({k: v for k, v in kwargs.items() if v is not None})
    return row


def text(title, subtitle=None, icon=None, accessory=None, destructive=False, value=None, on_click=None, **kwargs):
    return _row("text", title=title, subtitle=subtitle, icon=icon, accessory=accessory,
                destructive=destructive or None, value=value, on_click=on_click, **kwargs)


def switch(title, value=False, subtitle=None, on_change=None, key=None, **kwargs):
    return _row("switch", title=title, subtitle=subtitle, value=bool(value), on_change=on_change, key=key, **kwargs)


def input(placeholder="", value="", title=None, multiline=False, on_change=None, key=None, **kwargs):
    return _row("input", title=title, placeholder=placeholder, value=value or "",
                multiline=bool(multiline), on_change=on_change, key=key, **kwargs)


def button(title, style="default", on_click=None, **kwargs):
    return _row("button", title=title, style=style, on_click=on_click, **kwargs)


def selector(title, options, value=0, on_change=None, key=None, **kwargs):
    return _row("selector", title=title, options=[str(o) for o in options], value=int(value), on_change=on_change, key=key, **kwargs)


def grid_item(image=None, label=None, item_id=None, selected=False, badge=None, video=False, on_click=None, on_long_click=None):
    item = {"image": image, "label": label, "selected": bool(selected),
            "badge": badge, "video": bool(video), "on_click": on_click, "on_long_click": on_long_click}
    if item_id is not None:
        item["id"] = item_id
    return item


def grid(items, columns=3, item_height=112, on_click=None, **kwargs):
    return _row("grid", items=items, columns=int(columns), itemHeight=int(item_height), on_click=on_click, **kwargs)


def chips(options, selected=None, on_select=None, **kwargs):
    return _row("chips", options=[{"id": str(o.get("id", o)), "title": str(o.get("title", o)), "selected": bool(o.get("selected", False))} if isinstance(o, dict) else {"id": str(o), "title": str(o), "selected": str(o) == str(selected)} for o in options], on_select=on_select, **kwargs)


def image(path, height=200, **kwargs):
    return _row("image", image=path, height=int(height), **kwargs)


def section(rows=None, header=None, footer=None):
    return {"header": header, "footer": footer, "rows": rows or []}


def screen(title, sections=None, search=None, toolbar=None, bottom_button=None):
    return {"title": title, "sections": sections or [], "search": search, "toolbar": toolbar or [], "bottomButton": bottom_button}


def toolbar_item(icon, item_id=None, on_click=None):
    item = {"icon": icon, "on_click": on_click}
    if item_id is not None:
        item["id"] = item_id
    return item


def bottom_button(title, on_click=None, style="default"):
    return {"title": title, "style": style, "on_click": on_click}


# MARK: Presenting

class _Screen(object):
    def __init__(self, build, search_handler=None):
        self._build = build
        self._search_handler = search_handler
        self._id = _next_id()
        self._handlers = {}
        self._search_text = ""

    def _spec(self):
        self._handlers = {}
        spec = self._build() if callable(self._build) else self._build
        spec = dict(spec)
        spec["screenId"] = self._id
        spec["searchText"] = self._search_text
        self._register(spec)
        return spec

    def _register(self, spec):
        # Assign ids by position (stable across rebuilds) and pull callables into the handler
        # table, leaving the ids behind for the native side.
        for index, item in enumerate(spec.get("toolbar", [])):
            item.setdefault("id", "tb%d" % index)
            self._take(item, "on_click", item["id"])
        b = spec.get("bottomButton")
        if b:
            b.setdefault("id", "bottom")
            self._take(b, "on_click", b["id"])
        for si, sec in enumerate(spec.get("sections", [])):
            for ri, row in enumerate(sec.get("rows", [])):
                row.setdefault("id", "r%d_%d" % (si, ri))
                rid = row["id"]
                self._take(row, "on_click", rid)
                self._take(row, "on_change", rid)
                self._take(row, "on_select", rid)
                for ii, item in enumerate(row.get("items", []) or []):
                    item.setdefault("id", "%s_i%d" % (rid, ii))
                    self._take(item, "on_click", item["id"])
                    self._take(item, "on_long_click", item["id"] + ":long")

    def _take(self, holder, field, handler_id):
        fn = holder.pop(field, None)
        if callable(fn) and handler_id:
            self._handlers[(handler_id, field)] = fn

    def present(self):
        _screens[self._id] = self
        native("presentScreen", spec=self._spec())
        return self

    def update(self):
        if self._id in _screens:
            native("updateScreen", id=self._id, spec=self._spec())
        return self

    def dismiss(self):
        _screens.pop(self._id, None)
        native("dismissScreen", id=self._id)

    def event(self, event):
        kind = event.get("type")
        target = event.get("id")
        value = event.get("value")
        if kind == "search":
            self._search_text = value or ""
            if self._search_handler:
                self._search_handler(self._search_text)
            self.update()
            return
        if kind == "dismiss":
            _screens.pop(self._id, None)
            return
        field = {"tap": "on_click", "toggle": "on_change", "input": "on_change",
                 "select": "on_select", "longtap": "on_long_click"}.get(kind, "on_click")
        key = (target, field) if kind != "longtap" else (str(target) + ":long", "on_long_click")
        fn = self._handlers.get(key)
        if fn is None and field != "on_click":
            fn = self._handlers.get((target, "on_click"))
        if fn is None:
            return
        try:
            if value is None:
                fn()
            else:
                fn(value)
        except TypeError:
            fn()
        # After a handler runs, re-render so changes show.
        self.update()


def present(build, on_search=None):
    """Push a native screen. `build` is a dict or a function returning one (called on refresh)."""
    return _Screen(build, on_search).present()


def dismiss_all():
    for screen_obj in list(_screens.values()):
        screen_obj.dismiss()


def deliver_event(payload):
    screen_obj = _screens.get(payload.get("screenId"))
    if screen_obj is not None:
        screen_obj.event(payload)


# MARK: Quick helpers

def toast(text, kind="info"):
    native("bulletin", kind=kind, text=str(text))


def alert(title, message=None, buttons=None):
    import _lumen_host
    specs = []
    for which, (label, handler) in enumerate(buttons or [("OK", None)]):
        cb = _lumen_host.register_callback(handler) if handler else None
        specs.append({"which": -1 - which, "text": str(label), "callback": cb})
    native("alert", title=str(title), message=None if message is None else str(message),
           buttons=specs, items=None, itemsCallback=None, dismissCallback=None, progress=False)
