# bytearray for Skulpt, which has none. Installed as a builtin by _lumen_host. Backed by a
# list of ints; enough for buffers plugins read files into (buf = bytearray(8192)).


class bytearray(object):
    def __init__(self, source=None, encoding=None, errors=None):
        if source is None:
            self._data = []
        elif isinstance(source, int):
            self._data = [0] * source
        elif isinstance(source, str):
            self._data = list(source.encode(encoding or "utf-8"))
        else:
            self._data = [int(b) & 0xFF for b in source]

    def __len__(self):
        return len(self._data)

    def __iter__(self):
        return iter(self._data)

    def __getitem__(self, index):
        if isinstance(index, slice):
            result = bytearray()
            result._data = self._data[index]
            return result
        return self._data[index]

    def __setitem__(self, index, value):
        if isinstance(index, slice):
            if isinstance(value, bytearray):
                self._data[index] = list(value._data)
            else:
                self._data[index] = [int(b) & 0xFF for b in value]
        else:
            self._data[index] = int(value) & 0xFF

    def __eq__(self, other):
        try:
            return list(self) == list(other)
        except Exception:
            return False

    def __add__(self, other):
        result = bytearray()
        result._data = self._data + [int(b) & 0xFF for b in other]
        return result

    def __iadd__(self, other):
        self._data.extend(int(b) & 0xFF for b in other)
        return self

    def __contains__(self, value):
        return value in self._data

    def __repr__(self):
        return "bytearray(" + repr(bytes(self._data)) + ")"

    def append(self, value):
        self._data.append(int(value) & 0xFF)

    def extend(self, values):
        self._data.extend(int(b) & 0xFF for b in values)

    def clear(self):
        self._data = []

    def decode(self, encoding="utf-8", errors="strict"):
        return bytes(self._data).decode(encoding)

    def hex(self):
        return "".join(("0" + hex(b)[2:])[-2:] for b in self._data)

    def tobytes(self):
        return bytes(self._data)

    def find(self, sub, start=0):
        return bytes(self._data).find(bytes(list(sub)), start)

    def copy(self):
        result = bytearray()
        result._data = list(self._data)
        return result


def as_bytes(value):
    """bytes from bytes / bytearray / list of ints."""
    if isinstance(value, bytearray):
        return bytes(value._data)
    if isinstance(value, (bytes, str)):
        return value.encode("utf-8") if isinstance(value, str) else value
    return bytes(list(value))
