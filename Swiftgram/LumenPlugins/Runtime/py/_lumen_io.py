# File objects over the app's file bridge. Text files travel as UTF-8 strings, binary files
# as base64. Whole files are read on open and written on close (plugins' files are small).
import _lumen
from _lumen_bridge import native


def read_bytes(path):
    data = native("fs", action="readBase64", path=str(path))
    return _lumen.b64decode(data or "")


def write_bytes(path, data, append=False):
    from _lumen_bytearray import as_bytes
    native("fs", action="writeBase64", path=str(path), data=_lumen.b64encode(as_bytes(data)), append=bool(append))


def read_text(path):
    return native("fs", action="readText", path=str(path))


def write_text(path, text, append=False):
    native("fs", action="writeText", path=str(path), text=str(text), append=bool(append))


class LumenFile(object):
    def __init__(self, path, mode="r", encoding=None, *args, **kwargs):
        if hasattr(path, "__fspath__"):
            path = path.__fspath__()
        self.name = str(path)
        self.mode = mode
        self.closed = False
        self._binary = "b" in mode
        self._write = "w" in mode or "a" in mode or "+" in mode or "x" in mode
        self._append = "a" in mode
        self._pos = 0
        if "w" in mode or "x" in mode:
            self._data = b"" if self._binary else ""
            self._dirty = True
        else:
            exists = native("fs", action="exists", path=self.name)
            if not exists:
                if "a" in mode:
                    self._data = b"" if self._binary else ""
                    self._dirty = True
                    return
                raise FileNotFoundError("[Errno 2] No such file or directory: '" + self.name + "'")
            if self._binary:
                self._data = read_bytes(self.name)
            else:
                self._data = read_text(self.name) or ""
            self._dirty = False
            if self._append:
                self._pos = len(self._data)

    def read(self, size=-1):
        if size is None or size < 0:
            chunk = self._data[self._pos:]
        else:
            chunk = self._data[self._pos:self._pos + size]
        self._pos += len(chunk)
        return chunk

    def readline(self, *args):
        if self._binary:
            end = self._data.find(b"\n", self._pos)
        else:
            end = self._data.find("\n", self._pos)
        if end < 0:
            end = len(self._data)
        else:
            end += 1
        chunk = self._data[self._pos:end]
        self._pos = end
        return chunk

    def readlines(self, *args):
        lines = []
        while self._pos < len(self._data):
            lines.append(self.readline())
        return lines

    def __iter__(self):
        return iter(self.readlines())

    def write(self, data):
        if self._binary:
            from _lumen_bytearray import as_bytes
            data = as_bytes(data)
        else:
            data = str(data)
        self._data = self._data[:self._pos] + data + self._data[self._pos + len(data):]
        self._pos += len(data)
        self._dirty = True
        return len(data)

    def writelines(self, lines):
        for line in lines:
            self.write(line)

    def seek(self, offset, whence=0):
        if whence == 1:
            offset += self._pos
        elif whence == 2:
            offset += len(self._data)
        self._pos = max(0, offset)
        return self._pos

    def tell(self):
        return self._pos

    def flush(self):
        if self._dirty and self._write:
            if self._binary:
                write_bytes(self.name, self._data)
            else:
                write_text(self.name, self._data)
            self._dirty = False

    def close(self):
        if not self.closed:
            self.flush()
            self.closed = True

    def fileno(self):
        return 3

    def readable(self):
        return True

    def writable(self):
        return self._write

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
        return False


def lumen_open(file, mode="r", buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None):
    return LumenFile(file, mode, encoding)
