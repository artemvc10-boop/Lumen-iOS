# urllib.parse, the common parts.
_SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~"


def quote(string, safe="/", encoding="utf-8", errors=None):
    if isinstance(string, str):
        data = string.encode("utf-8")
    else:
        data = bytes(string)
    out = []
    for b in data:
        c = chr(b)
        if c in _SAFE or c in safe:
            out.append(c)
        else:
            out.append("%" + ("0" + hex(b)[2:].upper())[-2:])
    return "".join(out)


def quote_plus(string, safe="", encoding="utf-8", errors=None):
    return quote(string, safe + " ").replace(" ", "+")


def unquote(string, encoding="utf-8", errors="replace"):
    result = bytearray()
    i = 0
    while i < len(string):
        c = string[i]
        if c == "%" and i + 2 < len(string) + 1:
            try:
                result.append(int(string[i + 1:i + 3], 16))
                i += 3
                continue
            except Exception:
                pass
        result.extend(c.encode("utf-8"))
        i += 1
    return bytes(result).decode("utf-8")


def unquote_plus(string, encoding="utf-8", errors="replace"):
    return unquote(string.replace("+", " "))


def urlencode(query, doseq=False, safe="", encoding=None, errors=None, quote_via=quote_plus):
    if hasattr(query, "items"):
        query = list(query.items())
    parts = []
    for key, value in query:
        if doseq and isinstance(value, (list, tuple)):
            for item in value:
                parts.append(quote_via(str(key), safe) + "=" + quote_via(str(item), safe))
        else:
            parts.append(quote_via(str(key), safe) + "=" + quote_via(str(value), safe))
    return "&".join(parts)


class ParseResult(object):
    def __init__(self, scheme, netloc, path, params, query, fragment):
        self.scheme = scheme
        self.netloc = netloc
        self.path = path
        self.params = params
        self.query = query
        self.fragment = fragment

    def __iter__(self):
        return iter((self.scheme, self.netloc, self.path, self.params, self.query, self.fragment))

    def __getitem__(self, index):
        return list(self)[index]

    @property
    def hostname(self):
        host = self.netloc.split("@")[-1].split(":")[0]
        return host.lower() or None

    def geturl(self):
        return urlunparse(self)


def urlparse(url, scheme="", allow_fragments=True):
    fragment = ""
    query = ""
    if allow_fragments and "#" in url:
        url, fragment = url.split("#", 1)
    if "?" in url:
        url, query = url.split("?", 1)
    netloc = ""
    if "://" in url:
        scheme, url = url.split("://", 1)
        if "/" in url:
            netloc, url = url.split("/", 1)
            url = "/" + url
        else:
            netloc, url = url, ""
    return ParseResult(scheme, netloc, url, "", query, fragment)


urlsplit = urlparse


def urlunparse(parts):
    scheme, netloc, path, params, query, fragment = list(parts)
    url = ""
    if scheme:
        url += scheme + "://"
    url += netloc + path
    if query:
        url += "?" + query
    if fragment:
        url += "#" + fragment
    return url


urlunsplit = urlunparse


def parse_qsl(qs, keep_blank_values=False, *args, **kwargs):
    pairs = []
    for part in qs.split("&"):
        if not part:
            continue
        if "=" in part:
            key, value = part.split("=", 1)
        else:
            key, value = part, ""
        if value or keep_blank_values:
            pairs.append((unquote_plus(key), unquote_plus(value)))
    return pairs


def parse_qs(qs, keep_blank_values=False, *args, **kwargs):
    result = {}
    for key, value in parse_qsl(qs, keep_blank_values):
        result.setdefault(key, []).append(value)
    return result


def urljoin(base, url, allow_fragments=True):
    if "://" in url:
        return url
    parsed = urlparse(base)
    if url.startswith("/"):
        return parsed.scheme + "://" + parsed.netloc + url
    path = parsed.path.rsplit("/", 1)[0]
    return parsed.scheme + "://" + parsed.netloc + path + "/" + url
