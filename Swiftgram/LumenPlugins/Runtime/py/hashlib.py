# hashlib through the app (CommonCrypto).
import _lumen
from _lumen_bridge import native


class _Hash(object):
    def __init__(self, name, data=b""):
        self.name = name
        self._data = b""
        if data:
            self.update(data)

    def update(self, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        self._data += bytes(data)

    def hexdigest(self):
        return native("hash", algorithm=self.name, data=_lumen.b64encode(self._data))

    def digest(self):
        hexed = self.hexdigest()
        return bytes([int(hexed[i:i + 2], 16) for i in range(0, len(hexed), 2)])

    def copy(self):
        return _Hash(self.name, self._data)


def md5(data=b"", **kwargs):
    return _Hash("md5", data)


def sha1(data=b"", **kwargs):
    return _Hash("sha1", data)


def sha256(data=b"", **kwargs):
    return _Hash("sha256", data)


def sha512(data=b"", **kwargs):
    return _Hash("sha512", data)


def new(name, data=b"", **kwargs):
    return _Hash(name.lower(), data)
