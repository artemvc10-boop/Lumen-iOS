# AlertDialogBuilder, shown as a native alert.
from _lumen_bridge import native
from _lumen_java import JavaStub


class AlertDialogBuilder(object):
    ALERT_TYPE_MESSAGE = 0
    ALERT_TYPE_LOADING = 2
    ALERT_TYPE_SPINNER = 3
    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    def __init__(self, context=None, progress_style=0, resources_provider=None, *args, **kwargs):
        self._title = None
        self._message = None
        self._buttons = []
        self._items = None
        self._items_listener = None
        self._red = set()
        self._progress = progress_style in (2, 3)
        self._alert_id = None
        self._dismiss_listener = None

    def set_title(self, title):
        self._title = None if title is None else str(title)
        return self

    def set_message(self, message):
        self._message = None if message is None else str(message)
        return self

    def _add_button(self, which, text, listener):
        self._buttons = [b for b in self._buttons if b[0] != which]
        self._buttons.append((which, str(text), listener))
        return self

    def set_positive_button(self, text, listener=None):
        return self._add_button(self.BUTTON_POSITIVE, text, listener)

    def set_negative_button(self, text, listener=None):
        return self._add_button(self.BUTTON_NEGATIVE, text, listener)

    def set_neutral_button(self, text, listener=None):
        return self._add_button(self.BUTTON_NEUTRAL, text, listener)

    def set_items(self, items, listener=None, icons=None):
        self._items = [str(i) for i in items]
        self._items_listener = listener
        return self

    def make_button_red(self, which):
        self._red.add(which)
        return self

    def set_on_dismiss_listener(self, listener):
        self._dismiss_listener = listener
        return self

    def _noop(self, *args, **kwargs):
        return self

    set_cancelable = _noop
    set_canceled_on_touch_outside = _noop
    set_on_cancel_listener = _noop
    set_view = _noop
    set_top_image = _noop
    set_top_animation = _noop
    set_top_animation_is_new = _noop
    set_top_drawable = _noop
    set_dialog_button_color_key = _noop
    set_blurred_background = _noop
    set_dim_enabled = _noop
    set_progress = _noop
    set_message_text_view_clickable = _noop
    set_on_back_button_listener = _noop
    set_on_pre_dismiss_listener = _noop

    def create(self):
        return self

    def show(self):
        import _lumen_host
        buttons = []
        for which, text, listener in self._buttons:
            callback = None
            if listener is not None:
                callback = _lumen_host.register_callback(_bind_button(self, listener, which))
            buttons.append({"which": which, "text": text, "red": which in self._red, "callback": callback})
        items_callback = None
        if self._items_listener is not None:
            items_callback = _lumen_host.register_callback(_bind_items(self, self._items_listener))
        dismiss_callback = None
        if self._dismiss_listener is not None:
            dismiss_callback = _lumen_host.register_callback(_bind_dismiss(self, self._dismiss_listener))
        self._alert_id = native("alert", title=self._title, message=self._message, buttons=buttons, items=self._items,
                                itemsCallback=items_callback, dismissCallback=dismiss_callback, progress=self._progress)
        return self

    def dismiss(self):
        if self._alert_id is not None:
            native("dismissAlert", id=self._alert_id)
            self._alert_id = None

    def get_dialog(self):
        return JavaStub("AlertDialog")

    def get_button(self, which):
        return JavaStub("Button")

    def is_showing(self):
        return self._alert_id is not None


def _bind_button(builder, listener, which):
    def run(*args):
        listener(builder, which)
    return run


def _bind_items(builder, listener):
    def run(index=0, *args):
        listener(builder, int(index))
    return run


def _bind_dismiss(builder, listener):
    def run(*args):
        listener(builder)
    return run
