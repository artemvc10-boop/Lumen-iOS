# org.telegram.ui.ActionBar
import json
import _lumen_views
from _lumen_java import JavaStub
from _lumen_bridge import native
from _lumen_tg import Theme  # re-exported for plugins doing: from ...ActionBar import Theme

_dialog_counter = [0]


def _next_dialog_id():
    _dialog_counter[0] += 1
    return _dialog_counter[0]


class _Dialog(object):
    """Shared base for AlertDialog and BottomSheet — presents a view tree natively and keeps
    it in sync: after plugin code runs, a changed tree is sent again."""

    def __init__(self, context=None):
        self._id = _next_dialog_id()
        self._title = None
        self._message = None
        self._view = None
        self._buttons = []
        self._items = None
        self._items_listener = None
        self._dismiss_listener = None
        self._shown = False
        self._kind = "dialog"
        self._last_spec = None

    def _spec(self):
        return self._view._node() if self._view is not None else None

    def _present(self):
        import _lumen_host
        if self._items is not None and self._view is None:
            self._present_items()
            return
        buttons = []
        for which, text, listener in self._buttons:
            cb = _lumen_host.register_callback(_make_button_runner(self, listener, which)) if listener is not None else None
            buttons.append({"which": which, "text": str(text), "callback": cb})
        dismiss_cb = _lumen_host.register_view_callback(_make_dismiss_runner(self))
        spec = self._spec()
        self._last_spec = json.dumps(spec)
        native("presentView", id=self._id, kind=self._kind,
               title=None if self._title is None else str(self._title),
               message=None if self._message is None else str(self._message),
               view=spec, buttons=buttons, dismiss=dismiss_cb)
        self._shown = True
        _lumen_views._open_dialogs[self._id] = self

    def _present_items(self):
        import _lumen_host
        listener = self._items_listener
        dialog = self

        def on_item(index=0, *args):
            onClick = getattr(listener, "onClick", None)
            if callable(onClick):
                onClick(dialog, int(index))
            elif callable(listener):
                listener(dialog, int(index))
        items_cb = _lumen_host.register_callback(on_item) if listener is not None else None
        buttons = []
        for which, text, button_listener in self._buttons:
            cb = _lumen_host.register_callback(_make_button_runner(self, button_listener, which)) if button_listener is not None else None
            buttons.append({"which": which, "text": str(text), "callback": cb, "red": False})
        native("alert", title=None if self._title is None else str(self._title),
               message=None if self._message is None else str(self._message),
               buttons=buttons, items=self._items, itemsCallback=items_cb, dismissCallback=None, progress=False)

    def _refresh(self):
        if not self._shown or self._view is None:
            return
        spec = self._spec()
        encoded = json.dumps(spec)
        if encoded == self._last_spec:
            return
        self._last_spec = encoded
        native("updateView", id=self._id, view=spec)

    def show(self):
        self._present()
        return self

    def dismiss(self):
        if self._shown:
            self._shown = False
            native("dismissView", id=self._id)
        _lumen_views._open_dialogs.pop(self._id, None)

    cancel = dismiss

    def isShowing(self):
        return self._shown

    def setOnDismissListener(self, listener):
        self._dismiss_listener = listener
        return self

    def setTitle(self, title):
        self._title = title
        return self

    def setMessage(self, message):
        self._message = message
        return self

    def setView(self, view):
        self._view = view
        return self

    def getButton(self, which):
        return JavaStub("Button")

    def getContext(self):
        import _lumen_activity
        return _lumen_activity.current_activity()

    def getWindow(self):
        return JavaStub("Window")

    def __getattr__(self, key):
        if key.startswith("_"):
            raise AttributeError(key)

        def noop(*args, **kwargs):
            return self
        return noop


class AlertDialog(_Dialog):
    THEME_TYPE_LOADING = 1
    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    class OnButtonClickListener(object):
        pass

    class OnClickListener(object):
        pass

    def __init__(self, context=None, progressStyle=0, resourcesProvider=None, *args, **kwargs):
        _Dialog.__init__(self, context)
        self._kind = "dialog"

    def setPositiveButton(self, text, listener=None):
        self._buttons.append((-1, text, listener))
        return self

    def setNegativeButton(self, text, listener=None):
        self._buttons.append((-2, text, listener))
        return self

    class Builder(object):
        def __init__(self, context=None, *args, **kwargs):
            self._dialog = AlertDialog(context)

        def setTitle(self, title):
            self._dialog._title = title
            return self

        def setMessage(self, message):
            self._dialog._message = message
            return self

        def setView(self, view):
            self._dialog._view = view
            return self

        def setPositiveButton(self, text, listener=None):
            self._dialog._buttons.append((-1, text, listener))
            return self

        def setNegativeButton(self, text, listener=None):
            self._dialog._buttons.append((-2, text, listener))
            return self

        def setNeutralButton(self, text, listener=None):
            self._dialog._buttons.append((-3, text, listener))
            return self

        def setItems(self, items, *args):
            self._dialog._items = [str(i) for i in items]
            listener = None
            for arg in args:
                if arg is not None and not isinstance(arg, (list, tuple)):
                    listener = arg
            self._dialog._items_listener = listener
            return self

        def setOnDismissListener(self, listener):
            self._dialog._dismiss_listener = listener
            return self

        def create(self):
            return self._dialog

        def show(self):
            return self._dialog.show()

        def getContext(self):
            import _lumen_activity
            return _lumen_activity.current_activity()

        def __getattr__(self, key):
            if key.startswith("_"):
                raise AttributeError(key)

            def noop(*args, **kwargs):
                return self
            return noop


class BottomSheet(_Dialog):
    def __init__(self, context=None, needFocus=False, *args, **kwargs):
        _Dialog.__init__(self, context)
        self._kind = "bottom"

    def setCustomView(self, view):
        self._view = view
        return self

    def getContainerView(self):
        return self._view

    class Builder(object):
        def __init__(self, context=None, *args, **kwargs):
            self._sheet = BottomSheet(context)

        def setCustomView(self, view):
            self._sheet._view = view
            return self

        def setTitle(self, title, *args):
            self._sheet._title = title
            return self

        def setItems(self, items, *args):
            self._sheet._items = [str(i) for i in items]
            listener = None
            for arg in args:
                if arg is not None and not isinstance(arg, (list, tuple)):
                    listener = arg
            self._sheet._items_listener = listener
            return self

        def create(self):
            return self._sheet

        def show(self):
            return self._sheet.show()

        def __getattr__(self, key):
            if key.startswith("_"):
                raise AttributeError(key)

            def noop(*args, **kwargs):
                return self
            return noop


def _make_button_runner(dialog, listener, which):
    def run(*args):
        onClick = getattr(listener, "onClick", None)
        if callable(onClick):
            onClick(dialog, which)
        elif callable(listener):
            listener(dialog, which)
    return run


def _make_dismiss_runner(dialog):
    def run(*args):
        if not dialog._shown:
            _lumen_views._open_dialogs.pop(dialog._id, None)
            return
        dialog._shown = False
        _lumen_views._open_dialogs.pop(dialog._id, None)
        listener = dialog._dismiss_listener
        onDismiss = getattr(listener, "onDismiss", None)
        if callable(onDismiss):
            onDismiss(dialog)
        elif callable(listener):
            listener(dialog)
    return run


import _lumen_java
_lumen_java.fill_module(__name__)
