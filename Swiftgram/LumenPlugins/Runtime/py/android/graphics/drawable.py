# android.graphics.drawable


class GradientDrawable(object):
    RECTANGLE = 0
    OVAL = 1

    def __init__(self, *args, **kwargs):
        self._color = 0
        self._radius = 0.0
        self._radii = None
        self._strokeWidth = 0
        self._strokeColor = 0

    def setColor(self, color):
        try:
            self._color = int(color)
        except Exception:
            self._color = 0

    def setCornerRadius(self, radius):
        self._radius = float(radius)

    def setCornerRadii(self, radii):
        try:
            self._radii = [float(r) for r in radii]
        except Exception:
            self._radii = None

    def setStroke(self, width, color, *args):
        self._strokeWidth = int(width)
        try:
            self._strokeColor = int(color)
        except Exception:
            self._strokeColor = 0

    def setShape(self, shape):
        self._shape = shape

    def _spec(self):
        return {
            "color": self._color,
            "radius": self._radius,
            "radii": self._radii,
            "strokeWidth": self._strokeWidth,
            "strokeColor": self._strokeColor,
        }


class ColorDrawable(object):
    def __init__(self, color=0):
        try:
            self._color = int(color)
        except Exception:
            self._color = 0

    def _spec(self):
        return {"color": self._color, "radius": 0.0}


class Drawable(object):
    def __init__(self, *args, **kwargs):
        pass
