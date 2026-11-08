# android.text


class InputType:
    TYPE_CLASS_TEXT = 1
    TYPE_TEXT_FLAG_MULTI_LINE = 131072
    TYPE_TEXT_FLAG_CAP_SENTENCES = 16384
    TYPE_CLASS_NUMBER = 2
    TYPE_TEXT_VARIATION_PASSWORD = 128
    TYPE_NULL = 0


class Spanned:
    SPAN_EXCLUSIVE_EXCLUSIVE = 33
    SPAN_INCLUSIVE_INCLUSIVE = 18


class _SpannableBase(object):
    """A text builder plugins style with spans. Spans are dropped when rendered natively,
    but the text is kept, so str(...) gives the right string."""

    def __init__(self, text=""):
        self._text = "" if text is None else str(text)

    def setSpan(self, *args, **kwargs):
        return self

    def append(self, text):
        self._text += str(text)
        return self

    def toString(self):
        return self._text

    def __str__(self):
        return self._text

    def __len__(self):
        return len(self._text)


class SpannableStringBuilder(_SpannableBase):
    pass


class SpannableString(_SpannableBase):
    pass


class InputFilter(object):
    class LengthFilter(object):
        def __init__(self, maxLength):
            self.maxLength = int(maxLength)


class TextWatcher(object):
    pass


class TextUtils(object):
    @staticmethod
    def isEmpty(value):
        return value is None or str(value) == ""
