# java.io — files and byte streams over the app's file bridge.
import os


def _path_of(value):
    if hasattr(value, "getAbsolutePath"):
        return value.getAbsolutePath()
    return str(value)


class File(object):
    separator = "/"

    def __init__(self, parent, child=None):
        if child is not None:
            self._path = os.path.join(_path_of(parent), str(child))
        else:
            self._path = _path_of(parent)

    def getAbsolutePath(self):
        return self._path

    getPath = getAbsolutePath
    getCanonicalPath = getAbsolutePath

    def getName(self):
        return os.path.basename(self._path)

    def getParent(self):
        return os.path.dirname(self._path)

    def getParentFile(self):
        return File(os.path.dirname(self._path))

    def exists(self):
        return os.path.exists(self._path)

    def isDirectory(self):
        return os.path.isdir(self._path)

    def isFile(self):
        return os.path.isfile(self._path)

    def length(self):
        try:
            return os.path.getsize(self._path)
        except Exception:
            return 0

    def lastModified(self):
        try:
            return int(os.path.getmtime(self._path) * 1000)
        except Exception:
            return 0

    def delete(self):
        try:
            if os.path.isdir(self._path):
                import shutil
                shutil.rmtree(self._path)
            else:
                os.remove(self._path)
            return True
        except Exception:
            return False

    def mkdirs(self):
        try:
            os.makedirs(self._path, exist_ok=True)
            return True
        except Exception:
            return False

    mkdir = mkdirs

    def createNewFile(self):
        if os.path.exists(self._path):
            return False
        open(self._path, "wb").close()
        return True

    def renameTo(self, other):
        try:
            os.rename(self._path, _path_of(other))
            return True
        except Exception:
            return False

    def list(self):
        try:
            return os.listdir(self._path)
        except Exception:
            return None

    def listFiles(self, *args):
        names = self.list()
        if names is None:
            return None
        return [File(self._path, name) for name in names]

    def toString(self):
        return self._path

    def __str__(self):
        return self._path

    def __fspath__(self):
        return self._path


class FileOutputStream(object):
    def __init__(self, target, append=False):
        self._path = _path_of(target)
        self._append = bool(append)
        self._chunks = []
        self._closed = False

    def write(self, data, offset=None, length=None):
        from _lumen_bytearray import as_bytes
        if isinstance(data, int):
            self._chunks.append(bytes([data & 0xFF]))
            return
        if offset is not None and length is not None:
            data = data[int(offset):int(offset) + int(length)]
        self._chunks.append(as_bytes(data))

    def flush(self):
        pass

    def close(self):
        if self._closed:
            return
        self._closed = True
        import _lumen_io
        payload = b"".join(self._chunks)
        _lumen_io.write_bytes(self._path, payload, append=self._append)


class FileInputStream(object):
    def __init__(self, target):
        from _lumen_activity import _InStream
        self._stream = _InStream(_path_of(target))

    def read(self, buf=None, *args):
        return self._stream.read(buf)

    def available(self):
        return self._stream.available()

    def close(self):
        pass


class BufferedInputStream(FileInputStream):
    def __init__(self, stream, *args):
        self._stream = stream

    def read(self, buf=None, *args):
        return self._stream.read(buf)


class BufferedOutputStream(object):
    def __init__(self, stream, *args):
        self._stream = stream

    def write(self, *args):
        return self._stream.write(*args)

    def flush(self):
        pass

    def close(self):
        self._stream.close()


class IOException(Exception):
    pass


class FileNotFoundException(IOException):
    pass


import _lumen_java
_lumen_java.fill_module(__name__)
