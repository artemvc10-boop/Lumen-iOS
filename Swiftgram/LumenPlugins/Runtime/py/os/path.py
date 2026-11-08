# os.path, pure string handling plus a few file-bridge queries.
from _lumen_bridge import native

sep = "/"


def _str(p):
    if hasattr(p, "__fspath__"):
        return p.__fspath__()
    return str(p)


def join(a, *parts):
    result = _str(a)
    for part in parts:
        part = _str(part)
        if part.startswith("/"):
            result = part
        elif result == "" or result.endswith("/"):
            result += part
        else:
            result += "/" + part
    return result


def split(p):
    p = _str(p)
    i = p.rfind("/") + 1
    head, tail = p[:i], p[i:]
    if head and head != "/" * len(head):
        head = head.rstrip("/")
    return head, tail


def basename(p):
    return split(p)[1]


def dirname(p):
    return split(p)[0]


def splitext(p):
    p = _str(p)
    slash = p.rfind("/")
    dot = p.rfind(".")
    if dot > slash:
        start = slash + 1
        while start < dot and p[start] == ".":
            start += 1
        if start < dot:
            return p[:dot], p[dot:]
    return p, ""


def isabs(p):
    return _str(p).startswith("/")


def normpath(p):
    p = _str(p)
    if p == "":
        return "."
    absolute = p.startswith("/")
    parts = []
    for part in p.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if parts and parts[-1] != "..":
                parts.pop()
            elif not absolute:
                parts.append(part)
            continue
        parts.append(part)
    result = "/".join(parts)
    if absolute:
        return "/" + result
    return result or "."


def abspath(p):
    p = _str(p)
    if not isabs(p):
        p = join(native("fs", action="pluginsDir") or "/", p)
    return normpath(p)


def realpath(p, *args, **kwargs):
    return abspath(p)


def expanduser(p):
    p = _str(p)
    if p.startswith("~"):
        return "/storage/emulated/0" + p[1:]
    return p


def expandvars(p):
    return _str(p)


def exists(p):
    return bool(native("fs", action="exists", path=_str(p)))


lexists = exists


def isdir(p):
    return bool(native("fs", action="isDir", path=_str(p)))


def isfile(p):
    return exists(p) and not isdir(p)


def islink(p):
    return False


def ismount(p):
    return False


def getsize(p):
    info = native("fs", action="stat", path=_str(p))
    if info is None:
        raise FileNotFoundError("[Errno 2] No such file or directory: '" + _str(p) + "'")
    return int(info.get("size", 0))


def getmtime(p):
    info = native("fs", action="stat", path=_str(p))
    if info is None:
        raise FileNotFoundError("[Errno 2] No such file or directory: '" + _str(p) + "'")
    return float(info.get("mtime", 0))


getctime = getmtime
getatime = getmtime


def commonprefix(paths):
    if not paths:
        return ""
    s1 = min(paths)
    s2 = max(paths)
    for i, c in enumerate(s1):
        if c != s2[i]:
            return s1[:i]
    return s1


def relpath(p, start="."):
    p = abspath(p)
    start = abspath(start)
    if p.startswith(start.rstrip("/") + "/"):
        return p[len(start.rstrip("/")) + 1:]
    return p


def samefile(a, b):
    return abspath(a) == abspath(b)
