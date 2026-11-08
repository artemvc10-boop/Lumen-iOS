# Bulletins (toasts) shown by the app.
from _lumen_bridge import native


def _show(kind, text, subtitle=None, button=None, callback=None):
    callback_id = None
    if callback is not None:
        import _lumen_host
        callback_id = _lumen_host.register_callback(callback)
    native("bulletin", kind=kind, text="" if text is None else str(text), subtitle=None if subtitle is None else str(subtitle), button=button, callback=callback_id)


class BulletinHelper:
    DURATION_SHORT = 1500
    DURATION_LONG = 2750
    DURATION_PROLONG = 5000

    @staticmethod
    def show_info(message, fragment=None, *args, **kwargs):
        _show("info", message)

    @staticmethod
    def show_error(message, fragment=None, *args, **kwargs):
        _show("error", message)

    @staticmethod
    def show_success(message, fragment=None, *args, **kwargs):
        _show("success", message)

    @staticmethod
    def show_simple(text, icon_res_id=None, fragment=None, *args, **kwargs):
        _show("info", text)

    @staticmethod
    def show_two_line(title, subtitle, icon_res_id=None, fragment=None, *args, **kwargs):
        _show("info", title, subtitle)

    @staticmethod
    def show_with_button(text, icon_res_id=None, button_text="", on_click=None, fragment=None, *args, **kwargs):
        _show("info", text, button=str(button_text), callback=on_click)

    @staticmethod
    def show_undo(text, on_undo=None, on_action=None, subtitle=None, fragment=None, *args, **kwargs):
        _show("info", text, subtitle, button="Отменить", callback=on_undo)

    @staticmethod
    def show_copied_to_clipboard(message=None, fragment=None, *args, **kwargs):
        _show("success", message or "Скопировано")

    @staticmethod
    def show_link_copied(is_private_link_info=False, fragment=None, *args, **kwargs):
        _show("success", "Ссылка скопирована")

    @staticmethod
    def show_file_saved_to_gallery(is_video=False, amount=1, fragment=None, *args, **kwargs):
        _show("success", "Сохранено в галерею")

    @staticmethod
    def show_file_saved_to_downloads(file_type=None, amount=1, fragment=None, *args, **kwargs):
        _show("success", "Сохранено в загрузки")
