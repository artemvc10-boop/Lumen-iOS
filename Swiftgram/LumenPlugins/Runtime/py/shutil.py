# shutil over the app's file bridge.
from _lumen_bridge import native
import os


def _fs(action, **kwargs):
    return native("fs", action=action, **kwargs)


def _target(src, dst):
    if os.path.isdir(dst):
        return os.path.join(dst, os.path.basename(src))
    return dst


def copyfile(src, dst, *args, **kwargs):
    _fs("copy", src=str(src), dst=str(dst))
    return dst


def copy(src, dst, *args, **kwargs):
    dst = _target(src, dst)
    _fs("copy", src=str(src), dst=str(dst))
    return dst


copy2 = copy


def copytree(src, dst, *args, **kwargs):
    _fs("copy", src=str(src), dst=str(dst))
    return dst


def move(src, dst, *args, **kwargs):
    dst = _target(src, dst)
    _fs("move", src=str(src), dst=str(dst))
    return dst


def rmtree(p, ignore_errors=False, onerror=None, *args, **kwargs):
    try:
        if not os.path.exists(p):
            raise FileNotFoundError("[Errno 2] No such file or directory: '" + str(p) + "'")
        _fs("remove", path=str(p))
    except Exception as error:
        if ignore_errors:
            return
        if onerror is not None:
            onerror(rmtree, p, error)
            return
        raise


def copyfileobj(fsrc, fdst, length=0):
    fdst.write(fsrc.read())


def disk_usage(p):
    class _Usage(object):
        total = 64 * 1024 * 1024 * 1024
        used = 0
        free = 32 * 1024 * 1024 * 1024
    return _Usage()


def which(cmd, *args, **kwargs):
    return None


def make_archive(base_name, format="zip", root_dir=None, *args, **kwargs):
    target = base_name + ".zip"
    _fs("zipDir", src=str(root_dir or "."), dst=target)
    return target


def unpack_archive(filename, extract_dir=None, *args, **kwargs):
    native("zip", action="extract", path=str(filename), dst=str(extract_dir or os.path.dirname(filename)))
