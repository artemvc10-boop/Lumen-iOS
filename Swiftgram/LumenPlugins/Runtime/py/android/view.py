# android.view
from _lumen_views import View, dp


class Gravity:
    NO_GRAVITY = 0
    CENTER = 17
    CENTER_HORIZONTAL = 1
    CENTER_VERTICAL = 16
    LEFT = 3
    RIGHT = 5
    TOP = 48
    BOTTOM = 80
    START = 8388611
    END = 8388613
    FILL = 119
    FILL_HORIZONTAL = 7
    FILL_VERTICAL = 112


class MotionEvent:
    ACTION_DOWN = 0
    ACTION_UP = 1
    ACTION_MOVE = 2
    ACTION_CANCEL = 3

    def __init__(self):
        self._action = 0

    def getAction(self):
        return self._action


class WindowManager:
    class LayoutParams:
        pass


class ViewGroup(View):
    class LayoutParams(object):
        MATCH_PARENT = -1
        WRAP_CONTENT = -2

        def __init__(self, width=-2, height=-2, *args):
            self.width = width
            self.height = height

        def setMargins(self, left, top, right, bottom):
            self.leftMargin = left
            self.topMargin = top
            self.rightMargin = right
            self.bottomMargin = bottom

    class MarginLayoutParams(LayoutParams):
        pass


import _lumen_java
_lumen_java.fill_module(__name__)
