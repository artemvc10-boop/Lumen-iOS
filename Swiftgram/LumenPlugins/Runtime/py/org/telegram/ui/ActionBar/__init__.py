# org.telegram.ui.ActionBar
from _lumen_java import JavaStub
from _lumen_bridge import native
from _lumen_tg import Theme  # re-exported for plugins doing: from ...ActionBar import Theme

_dialogs = {}
_dialog_counter = [0]


def _next_dialog_id():
    _dialog_counter[0] += 1
    return _dialog_counter[0]


class _Dialog(object):
    """Shared base for AlertDialog and BottomSheet — presents a view tree natively."""

    def __init__(self, context=None):
        self._id = _next_dialog_id()
        self._title = None
        self._message = None
        self._view = None
        self._buttons = []
        self._dismiss_listener = None
        self._shown = False
        self._kind = "dialog"
        _dialogs[self._id] = self

    def _present(self):
        import _lumen_host
        buttons = []
        for which, text, listener in self._buttons:
            cb = _lumen_host.register_callback(_make_button_runner(self, listener, which)) if listener is not None else None
            buttons.append({"which": which, "text": str(text), "callback": cb, "red": which == -1 and False})
        dismiss_cb = None
        if self._dismiss_listener is not None:
            dismiss_cb = _lumen_host.register_callback(_make_dismiss_runner(self))
        spec = self._view._node() if self._view is not None else None
        native("presentView", id=self._id, kind=self._kind,
               title=None if self._title is None else str(self._title),
               message=None if self._message is None else str(self._message),
               view=spec, buttons=buttons, dismiss=dismiss_cb)
        self._shown = True

    def show(self):
        self._present()
        return self

    def dismiss(self):
        if self._shown:
            native("dismissView", id=self._id)
            self._shown = False
        _dialogs.pop(self._id, None)

    def isShowing(self):
        return self._shown

    def setOnDismissListener(self, listener):
        self._dismiss_listener = listener
        return self

    def getButton(self, which):
        return JavaStub("Button")

    def getContext(self):
        return JavaStub("Context")

    def __getattr__(self, key):
        if key.startswith("__") and key.endswith("__"):
            raise AttributeError(key)

        def noop(*args, **kwargs):
            return self
        return noop


class AlertDialog(_Dialog):
    THEME_TYPE_LOADING = 1

    class OnButtonClickListener(object):
        pass

    def __init__(self, context=None, progressStyle=0, resourcesProvider=None):
        _Dialog.__init__(self, context)
        self._kind = "dialog"

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

        def setItems(self, items, listener=None):
            self._dialog._items = [str(i) for i in items]
            self._dialog._items_listener = listener
            return self

        def setOnDismissListener(self, listener):
            self._dialog._dismiss_listener = listener
            return self

        def create(self):
            return self._dialog

        def show(self):
            return self._dialog.show()

        def __getattr__(self, key):
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

    def setApplyTopPadding(self, *args):
        return self

    def setApplyBottomPadding(self, *args):
        return self

    class Builder(object):
        def __init__(self, context=None, *args, **kwargs):
            self._sheet = BottomSheet(context)

        def setCustomView(self, view):
            self._sheet._view = view
            return self

        def setTitle(self, title, *args):
            self._sheet._title = title
            return self

        def create(self):
            return self._sheet

        def show(self):
            return self._sheet.show()

        def __getattr__(self, key):
            def noop(*args, **kwargs):
                return self
            return noop


def _make_button_runner(dialog, listener, which):
    def run():
        onClick = getattr(listener, "onClick", None)
        if callable(onClick):
            onClick(dialog, which)
    return run


def _make_dismiss_runner(dialog):
    def run():
        dialog._shown = False
        listener = dialog._dismiss_listener
        onDismiss = getattr(listener, "onDismiss", None)
        if callable(onDismiss):
            onDismiss(dialog)
    return run
