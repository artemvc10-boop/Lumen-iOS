# os over the app's file bridge. Android paths (/storage/emulated/0/...) are mapped by the
# app into its Documents folder.
from _lumen_bridge import native
import os.path as path

sep = "/"
pathsep = ":"
linesep = "\n"
curdir = "."
pardir = ".."
extsep = "."
altsep = None
devnull = "/dev/null"
name = "posix"
environ = {"HOME": "/storage/emulated/0", "EXTERNAL_STORAGE": "/storage/emulated/0"}
F_OK = 0
R_OK = 4
W_OK = 2
X_OK = 1


def _fs(action, **kwargs):
    return native("fs", action=action, **kwargs)


def fspath(p):
    if hasattr(p, "__fspath__"):
        return p.__fspath__()
    return str(p)


def getcwd():
    return _fs("pluginsDir")


def getenv(key, default=None):
    return environ.get(key, default)


def listdir(p="."):
    result = _fs("list", path=fspath(p))
    if result is None:
        raise FileNotFoundError("[Errno 2] No such file or directory: '" + fspath(p) + "'")
    return result


def scandir(p="."):
    entries = []
    base = fspath(p)
    for item in listdir(base):
        entries.append(DirEntry(path.join(base, item), item))
    return iter(entries)


class DirEntry(object):
    def __init__(self, full, name):
        self.path = full
        self.name = name

    def is_dir(self, follow_symlinks=True):
        return path.isdir(self.path)

    def is_file(self, follow_symlinks=True):
        return path.isfile(self.path)

    def stat(self, follow_symlinks=True):
        return stat(self.path)


def mkdir(p, mode=0o777, *args, **kwargs):
    if path.exists(p):
        raise FileExistsError("[Errno 17] File exists: '" + fspath(p) + "'")
    _fs("mkdir", path=fspath(p), parents=False)


def makedirs(p, mode=0o777, exist_ok=False):
    if path.isdir(p):
        if exist_ok:
            return
        raise FileExistsError("[Errno 17] File exists: '" + fspath(p) + "'")
    _fs("mkdir", path=fspath(p), parents=True)


def remove(p, *args, **kwargs):
    if not path.exists(p):
        raise FileNotFoundError("[Errno 2] No such file or directory: '" + fspath(p) + "'")
    _fs("remove", path=fspath(p))


unlink = remove


def rmdir(p, *args, **kwargs):
    _fs("remove", path=fspath(p))


def removedirs(p):
    _fs("remove", path=fspath(p))


def rename(src, dst, *args, **kwargs):
    _fs("move", src=fspath(src), dst=fspath(dst))


replace = rename
renames = rename


class stat_result(object):
    def __init__(self, info):
        self.st_size = int(info.get("size", 0))
        self.st_mtime = float(info.get("mtime", 0))
        self.st_ctime = float(info.get("ctime", self.st_mtime))
        self.st_atime = self.st_mtime
        self.st_mode = 0o40755 if info.get("isDir") else 0o100644


def stat(p, *args, **kwargs):
    info = _fs("stat", path=fspath(p))
    if info is None:
        raise FileNotFoundError("[Errno 2] No such file or directory: '" + fspath(p) + "'")
    return stat_result(info)


lstat = stat


def access(p, mode, *args, **kwargs):
    return path.exists(p)


def walk(top, topdown=True, onerror=None, followlinks=False):
    top = fspath(top)
    try:
        names = listdir(top)
    except Exception as error:
        if onerror is not None:
            onerror(error)
        return
    dirs = []
    nondirs = []
    for item in names:
        if path.isdir(path.join(top, item)):
            dirs.append(item)
        else:
            nondirs.append(item)
    result = []
    if topdown:
        result.append((top, dirs, nondirs))
        for item in dirs:
            result.extend(walk(path.join(top, item), topdown, onerror, followlinks))
    else:
        for item in dirs:
            result.extend(walk(path.join(top, item), topdown, onerror, followlinks))
        result.append((top, dirs, nondirs))
    return result


def urandom(n):
    import random
    return bytes([random.randint(0, 255) for _ in range(n)])


def getpid():
    return 1


def cpu_count():
    return 6


def system(command):
    return -1


def chmod(*args, **kwargs):
    pass


def utime(*args, **kwargs):
    pass
