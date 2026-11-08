# io: in-memory streams; open() is the app-backed file.
from _lumen_io import lumen_open as open, LumenFile as FileIO


class _Memory(object):
    def __init__(self, initial, empty):
        self._data = empty if initial is None else initial
        self._pos = 0
        self.closed = False

    def read(self, size=-1):
        if size is None or size < 0:
            chunk = self._data[self._pos:]
        else:
            chunk = self._data[self._pos:self._pos + size]
        self._pos += len(chunk)
        return chunk

    def write(self, data):
        self._data = self._data[:self._pos] + data + self._data[self._pos + len(data):]
        self._pos += len(data)
        return len(data)

    def getvalue(self):
        return self._data

    def seek(self, offset, whence=0):
        if whence == 1:
            offset += self._pos
        elif whence == 2:
            offset += len(self._data)
        self._pos = max(0, offset)
        return self._pos

    def tell(self):
        return self._pos

    def close(self):
        self.closed = True

    def flush(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class StringIO(_Memory):
    def __init__(self, initial_value="", newline=None):
        _Memory.__init__(self, initial_value, "")

    def readline(self, *args):
        end = self._data.find("\n", self._pos)
        end = len(self._data) if end < 0 else end + 1
        chunk = self._data[self._pos:end]
        self._pos = end
        return chunk


class BytesIO(_Memory):
    def __init__(self, initial_bytes=b""):
        _Memory.__init__(self, bytes(initial_bytes), b"")


TextIOWrapper = StringIO
BufferedReader = BytesIO
