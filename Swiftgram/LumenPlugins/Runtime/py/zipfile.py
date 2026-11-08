# zipfile on top of the app: writing collects entries and builds the archive on close,
# reading extracts through the app.
import _lumen
from _lumen_bridge import native
import os

ZIP_STORED = 0
ZIP_DEFLATED = 8
ZIP_BZIP2 = 12
ZIP_LZMA = 14


class BadZipFile(Exception):
    pass


BadZipfile = BadZipFile


class ZipInfo(object):
    def __init__(self, filename="", date_time=(1980, 1, 1, 0, 0, 0)):
        self.filename = filename
        self.date_time = date_time
        self.file_size = 0
        self.compress_size = 0

    def is_dir(self):
        return self.filename.endswith("/")


def is_zipfile(filename):
    try:
        info = native("zip", action="list", path=str(filename))
        return info is not None
    except Exception:
        return False


class ZipFile(object):
    def __init__(self, file, mode="r", compression=ZIP_STORED, allowZip64=True, *args, **kwargs):
        if hasattr(file, "name") and not isinstance(file, str):
            file = file.name
        self.filename = str(file)
        self.mode = mode
        self._entries = []
        self._names = None
        if mode == "r":
            names = native("zip", action="list", path=self.filename)
            if names is None:
                raise BadZipFile("File is not a zip file")
            self._names = names
        elif mode == "a" and os.path.exists(self.filename):
            self._names = native("zip", action="list", path=self.filename) or []

    def namelist(self):
        if self._names is not None:
            return list(self._names) + [e["name"] for e in self._entries]
        return [e["name"] for e in self._entries]

    def infolist(self):
        return [ZipInfo(n) for n in self.namelist()]

    def getinfo(self, name):
        return ZipInfo(name)

    def write(self, filename, arcname=None, *args, **kwargs):
        if arcname is None:
            arcname = os.path.basename(filename)
        self._entries.append({"name": str(arcname), "path": str(filename)})

    def writestr(self, zinfo_or_arcname, data, *args, **kwargs):
        name = zinfo_or_arcname.filename if isinstance(zinfo_or_arcname, ZipInfo) else str(zinfo_or_arcname)
        if isinstance(data, str):
            data = data.encode("utf-8")
        self._entries.append({"name": name, "data": _lumen.b64encode(bytes(data))})

    def read(self, name, *args, **kwargs):
        data = native("zip", action="read", path=self.filename, name=str(name))
        if data is None:
            raise KeyError("There is no item named '" + str(name) + "' in the archive")
        return _lumen.b64decode(data)

    def open(self, name, mode="r", *args, **kwargs):
        import io
        return io.BytesIO(self.read(name))

    def extract(self, member, path=None, *args, **kwargs):
        name = member.filename if isinstance(member, ZipInfo) else str(member)
        target = path or "."
        native("zip", action="extract", path=self.filename, dst=str(target), names=[name])
        return os.path.join(target, name)

    def extractall(self, path=None, members=None, *args, **kwargs):
        names = None
        if members is not None:
            names = [m.filename if isinstance(m, ZipInfo) else str(m) for m in members]
        native("zip", action="extract", path=self.filename, dst=str(path or "."), names=names)

    def testzip(self):
        return None

    def close(self):
        if self.mode in ("w", "x", "a") and self._entries is not None:
            native("zip", action="create", path=self.filename, entries=self._entries, append=self.mode == "a")
            self._entries = []
            self.mode = "closed"

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
        return False
