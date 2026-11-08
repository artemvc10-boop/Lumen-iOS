# uuid through the app.
from _lumen_bridge import native


class UUID(object):
    def __init__(self, hex=None, *args, **kwargs):
        self.hex = (hex or "").replace("-", "").lower()

    def __str__(self):
        h = self.hex
        return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]

    def __repr__(self):
        return "UUID('" + str(self) + "')"

    def __eq__(self, other):
        return isinstance(other, UUID) and other.hex == self.hex

    def __hash__(self):
        return hash(self.hex)


def uuid4():
    return UUID(native("uuid"))


uuid1 = uuid4
