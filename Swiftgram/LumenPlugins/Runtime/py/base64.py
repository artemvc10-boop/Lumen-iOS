# base64 through the host.
import _lumen


def _bytes(data):
    if isinstance(data, str):
        return data.encode("utf-8")
    return bytes(data)


def b64encode(data, altchars=None):
    text = _lumen.b64encode(_bytes(data))
    if altchars is not None:
        altchars = _bytes(altchars).decode("ascii")
        text = text.replace("+", altchars[0]).replace("/", altchars[1])
    return text.encode("ascii")


def b64decode(data, altchars=None, validate=False):
    if isinstance(data, bytes):
        data = data.decode("ascii")
    if altchars is not None:
        altchars = _bytes(altchars).decode("ascii")
        data = data.replace(altchars[0], "+").replace(altchars[1], "/")
    data = "".join(data.split())
    data += "=" * (-len(data) % 4)
    return _lumen.b64decode(data)


def urlsafe_b64encode(data):
    return b64encode(data, b"-_")


def urlsafe_b64decode(data):
    return b64decode(data, b"-_")


standard_b64encode = b64encode
standard_b64decode = b64decode
encodebytes = b64encode
decodebytes = b64decode
