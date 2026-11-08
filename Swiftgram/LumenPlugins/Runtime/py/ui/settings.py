# exteraGram plugin settings items. The app renders them natively from to_json().


class _Item(object):
    kind = "unknown"

    def to_json(self):
        return {"type": self.kind}


class Header(_Item):
    kind = "header"

    def __init__(self, text="", **kwargs):
        self.text = text

    def to_json(self):
        return {"type": self.kind, "text": str(self.text)}


class Divider(_Item):
    kind = "divider"

    def __init__(self, text=None, **kwargs):
        self.text = text

    def to_json(self):
        return {"type": self.kind, "text": "" if self.text is None else str(self.text)}


class Switch(_Item):
    kind = "switch"

    def __init__(self, key, text, default=False, subtext=None, icon=None, on_change=None, link_alias=None, on_long_click=None, **kwargs):
        self.key = key
        self.text = text
        self.default = default
        self.subtext = subtext
        self.icon = icon
        self.on_change = on_change
        self.on_long_click = on_long_click

    def to_json(self):
        return {"type": self.kind, "key": str(self.key), "text": str(self.text), "default": bool(self.default), "subtext": None if self.subtext is None else str(self.subtext), "icon": self.icon}


class Input(_Item):
    kind = "input"

    def __init__(self, key, text, default="", subtext=None, icon=None, on_change=None, link_alias=None, **kwargs):
        self.key = key
        self.text = text
        self.default = default
        self.subtext = subtext
        self.icon = icon
        self.on_change = on_change

    def to_json(self):
        return {"type": self.kind, "key": str(self.key), "text": str(self.text), "default": "" if self.default is None else str(self.default), "subtext": None if self.subtext is None else str(self.subtext), "icon": self.icon}


class EditText(_Item):
    kind = "edit_text"

    def __init__(self, key, hint="", default="", multiline=False, max_length=None, mask=None, on_change=None, **kwargs):
        self.key = key
        self.hint = hint
        self.default = default
        self.multiline = multiline
        self.max_length = max_length
        self.on_change = on_change

    def to_json(self):
        return {"type": self.kind, "key": str(self.key), "text": str(self.hint), "default": "" if self.default is None else str(self.default), "multiline": bool(self.multiline), "maxLength": self.max_length}


class Selector(_Item):
    kind = "selector"

    def __init__(self, key, text, default=0, items=None, icon=None, on_change=None, link_alias=None, **kwargs):
        self.key = key
        self.text = text
        self.default = default
        self.items = list(items or [])
        self.icon = icon
        self.on_change = on_change

    def to_json(self):
        return {"type": self.kind, "key": str(self.key), "text": str(self.text), "default": int(self.default or 0), "items": [str(i) for i in self.items], "icon": self.icon}


class Text(_Item):
    kind = "text"

    def __init__(self, text, icon=None, accent=False, red=False, on_click=None, create_sub_fragment=None, link_alias=None, on_long_click=None, subtext=None, **kwargs):
        self.text = text
        self.icon = icon
        self.accent = accent
        self.red = red
        self.on_click = on_click
        self.create_sub_fragment = create_sub_fragment
        self.on_long_click = on_long_click
        self.subtext = subtext

    def to_json(self):
        return {"type": self.kind, "text": str(self.text), "icon": self.icon, "accent": bool(self.accent), "red": bool(self.red),
                "clickable": self.on_click is not None, "hasSubpage": self.create_sub_fragment is not None,
                "subtext": None if self.subtext is None else str(self.subtext)}


class Custom(_Item):
    kind = "custom"

    def __init__(self, *args, **kwargs):
        pass


class Label(Text):
    pass
