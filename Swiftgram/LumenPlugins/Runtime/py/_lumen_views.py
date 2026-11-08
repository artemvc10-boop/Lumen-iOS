# A small Android view tree. Plugins build views (LinearLayout, TextView, EditText, ...)
# the way they do on Android; Lumen turns the tree into native UIKit and sends taps and text
# back. Only layout, text, input, images and backgrounds are modelled — enough for the forms
# and sheets plugins build.
from _lumen_java import JavaStub

_views = {}
_counter = [0]


def _register(view):
    _counter[0] += 1
    vid = _counter[0]
    view._vid = vid
    _views[vid] = view
    return vid


def view_for(vid):
    return _views.get(vid)


def set_view_text(vid, value):
    view = _views.get(vid)
    if view is not None:
        view._text = "" if value is None else str(value)


def _make_click(listener, view):
    def run():
        onClick = getattr(listener, "onClick", None)
        if callable(onClick):
            onClick(view)
    return run


def _make_long_click(listener, view):
    def run():
        onLongClick = getattr(listener, "onLongClick", None)
        if callable(onLongClick):
            onLongClick(view)
    return run


def dp(value):
    return int(value)


class View(object):
    VISIBLE = 0
    INVISIBLE = 4
    GONE = 8

    # Listener interfaces plugins subclass via dynamic_proxy(View.OnClickListener).
    class OnClickListener(object):
        pass

    class OnLongClickListener(object):
        pass

    class OnTouchListener(object):
        pass

    class OnFocusChangeListener(object):
        pass

    def __init__(self, context=None):
        self._vid = _register(self)
        self._children = []
        self._text = ""
        self._props = {}
        self._listeners = {}
        self._visibility = View.VISIBLE
        self._enabled = True

    # Layout and style setters plugins call. Unknown ones are swallowed.
    def __getattr__(self, key):
        if key.startswith("__") and key.endswith("__"):
            raise AttributeError(key)

        def setter(*args, **kwargs):
            return _Animator()
        return setter

    def _set(self, key, value):
        self._props[key] = value

    def setText(self, text):
        self._text = "" if text is None else str(text)

    def getText(self):
        return _Editable(self)

    def setHint(self, hint):
        self._props["hint"] = "" if hint is None else str(hint)

    def setTextColor(self, color):
        self._props["textColor"] = _color_int(color)

    def setHintTextColor(self, color):
        self._props["hintColor"] = _color_int(color)

    def setTextSize(self, unit, size=None):
        self._props["textSize"] = float(size if size is not None else unit)

    def setTextSizeDirect(self, size):
        self._props["textSize"] = float(size)

    def setPadding(self, left, top, right, bottom):
        self._props["padding"] = [int(left), int(top), int(right), int(bottom)]

    def setGravity(self, gravity):
        self._props["gravity"] = int(gravity)

    def setBackground(self, drawable):
        self._props["background"] = drawable._spec() if hasattr(drawable, "_spec") else None

    def setBackgroundColor(self, color):
        self._props["background"] = {"color": _color_int(color), "radius": 0}

    def setVisibility(self, visibility):
        self._visibility = int(visibility)

    def getVisibility(self):
        return self._visibility

    def setEnabled(self, value):
        self._enabled = bool(value)

    def setSingleLine(self, value=True):
        self._props["singleLine"] = bool(value)

    def setMaxLines(self, value):
        self._props["maxLines"] = int(value)

    def setAlpha(self, value):
        self._props["alpha"] = float(value)

    def setClickable(self, value):
        self._props["clickable"] = bool(value)

    def setImageBitmap(self, bitmap):
        self._props["image"] = _bitmap_path(bitmap)

    def setImageResource(self, resource):
        pass

    def setImageDrawable(self, drawable):
        pass

    def setScaleType(self, scaleType):
        self._props["scaleType"] = str(scaleType)

    def setInputType(self, inputType):
        value = int(inputType) if isinstance(inputType, (int, float)) else 1
        self._props["inputType"] = value
        if value & 131072:  # TYPE_TEXT_FLAG_MULTI_LINE
            self._props["singleLine"] = False

    def setFilters(self, filters):
        for item in filters or []:
            maxLength = getattr(item, "maxLength", None)
            if maxLength is not None:
                self._props["maxLength"] = int(maxLength)

    def setOnClickListener(self, listener):
        self._listeners["click"] = listener

    def setOnLongClickListener(self, listener):
        self._listeners["longClick"] = listener

    def setOnTouchListener(self, listener):
        self._listeners["touch"] = listener

    class LayoutParams(object):
        MATCH_PARENT = -1
        WRAP_CONTENT = -2
        FILL_PARENT = -1

        def __init__(self, width=-2, height=-2, weight=0.0):
            self.width = width
            self.height = height
            self.weight = weight
            self.gravity = -1
            self.leftMargin = 0
            self.topMargin = 0
            self.rightMargin = 0
            self.bottomMargin = 0

        def setMargins(self, left, top, right, bottom):
            self.leftMargin = int(left)
            self.topMargin = int(top)
            self.rightMargin = int(right)
            self.bottomMargin = int(bottom)

    def setLayoutParams(self, params):
        self._apply_params(params)

    def _apply_params(self, params):
        if params is None:
            return
        self._props["layout"] = {
            "width": getattr(params, "width", -2),
            "height": getattr(params, "height", -2),
            "weight": getattr(params, "weight", 0.0),
            "gravity": getattr(params, "gravity", -1),
            "margins": [getattr(params, "leftMargin", 0), getattr(params, "topMargin", 0), getattr(params, "rightMargin", 0), getattr(params, "bottomMargin", 0)],
        }

    def addView(self, child, params=None):
        if isinstance(child, View):
            if params is not None:
                child._apply_params(params)
            self._children.append(child)

    def removeAllViews(self):
        self._children = []

    def removeView(self, child):
        if child in self._children:
            self._children.remove(child)

    def getChildCount(self):
        return len(self._children)

    def getChildAt(self, index):
        if 0 <= index < len(self._children):
            return self._children[index]
        return None

    def getParent(self):
        return JavaStub("ViewParent")

    def animate(self):
        return _Animator()

    def requestLayout(self):
        pass

    def invalidate(self):
        pass

    def _node(self):
        import _lumen_host
        node = {
            "vid": self._vid,
            "type": self._view_type(),
            "text": self._text,
            "props": self._props,
            "visibility": self._visibility,
            "children": [child._node() for child in self._children],
        }
        click = self._listeners.get("click")
        if click is not None:
            node["clickCallback"] = _lumen_host.register_view_callback(_make_click(click, self))
        longClick = self._listeners.get("longClick")
        if longClick is not None:
            node["longClickCallback"] = _lumen_host.register_view_callback(_make_long_click(longClick, self))
        return node

    def _view_type(self):
        return "view"


class _Editable(object):
    """What getText() returns; str(...) / .toString() gives the current text."""

    def __init__(self, view):
        self._view = view

    def toString(self):
        return self._view._text

    def __str__(self):
        return self._view._text

    def __len__(self):
        return len(self._view._text)

    def clear(self):
        self._view._text = ""

    def append(self, text):
        self._view._text += str(text)


class _Animator(object):
    """Chainable no-op animator: v.animate().scaleX(..).setDuration(..).start()."""

    def __getattr__(self, key):
        def chain(*args, **kwargs):
            # withEndAction(runnable) should still run the action.
            for arg in args:
                run = getattr(arg, "run", None)
                if callable(run):
                    import _lumen_host
                    _lumen_host.safe_call(run)
            return self
        return chain


def _color_int(color):
    try:
        return int(color)
    except Exception:
        return 0


def _bitmap_path(bitmap):
    if bitmap is None:
        return None
    path = getattr(bitmap, "_lumen_path", None)
    return path


class LinearLayout(View):
    HORIZONTAL = 0
    VERTICAL = 1

    def setOrientation(self, orientation):
        self._props["orientation"] = int(orientation)

    def _view_type(self):
        return "linear"


class FrameLayout(View):
    def _view_type(self):
        return "frame"


class RelativeLayout(View):
    def _view_type(self):
        return "frame"


class ScrollView(View):
    def _view_type(self):
        return "scroll"


class HorizontalScrollView(View):
    def _view_type(self):
        return "hscroll"


class TextView(View):
    def _view_type(self):
        return "text"


class Button(TextView):
    def _view_type(self):
        return "button"


class EditText(View):
    def _view_type(self):
        return "edit"


class ImageView(View):
    class ScaleType(object):
        CENTER_CROP = "centerCrop"
        FIT_CENTER = "fitCenter"
        CENTER = "center"

    def _view_type(self):
        return "image"
