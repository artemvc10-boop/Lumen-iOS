# android.text.style — span types. Dropped at render time, so they are inert markers.


class ForegroundColorSpan(object):
    def __init__(self, color=0):
        self.color = color


class BackgroundColorSpan(object):
    def __init__(self, color=0):
        self.color = color


class StyleSpan(object):
    def __init__(self, style=0):
        self.style = style


class RelativeSizeSpan(object):
    def __init__(self, size=1.0):
        self.size = size


class ImageSpan(object):
    def __init__(self, *args, **kwargs):
        pass


class UnderlineSpan(object):
    pass


import _lumen_java
_lumen_java.fill_module(__name__)
