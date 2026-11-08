# org.telegram.ui.Components
from _lumen_java import JavaStub
from _lumen_views import EditText, ImageView, View


class EditTextBoldCursor(EditText):
    def setCursorColor(self, color):
        pass

    def setCursorSize(self, size):
        pass

    def setCursorWidth(self, width):
        pass


class BackupImageView(ImageView):
    def setImage(self, *args, **kwargs):
        pass

    def setRoundRadius(self, *args, **kwargs):
        pass


class BulletinFactory(object):
    @staticmethod
    def of(*args, **kwargs):
        return JavaStub("BulletinFactory")

    @staticmethod
    def global_():
        return JavaStub("BulletinFactory")


class LayoutHelper(object):
    MATCH_PARENT = -1
    WRAP_CONTENT = -2

    @staticmethod
    def createLinear(width, height, *args, **kwargs):
        from _lumen_views import View
        params = View.LayoutParams(width, height)
        if args:
            # createLinear(w, h, gravity) or (w, h, l, t, r, b)
            if len(args) == 1:
                params.gravity = args[0]
            elif len(args) >= 4:
                params.setMargins(args[-4], args[-3], args[-2], args[-1])
        return params

    @staticmethod
    def createFrame(width, height, *args, **kwargs):
        return LayoutHelper.createLinear(width, height, *args, **kwargs)

    @staticmethod
    def createScroll(width, height, *args, **kwargs):
        from _lumen_views import View
        return View.LayoutParams(width, height)


def __getattr__(name):
    return JavaStub("Components." + name)
