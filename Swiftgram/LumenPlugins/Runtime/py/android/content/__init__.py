# android.content
from _lumen_activity import Intent, ContentResolver, Activity as Context


class DialogInterface(object):
    BUTTON_POSITIVE = -1
    BUTTON_NEGATIVE = -2
    BUTTON_NEUTRAL = -3

    class OnClickListener(object):
        pass

    class OnDismissListener(object):
        pass

    class OnCancelListener(object):
        pass


class ClipboardManager(object):
    pass


class ClipData(object):
    @staticmethod
    def newPlainText(label, text):
        return text


import _lumen_java
_lumen_java.fill_module(__name__)
