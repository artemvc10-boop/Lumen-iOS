# requests over the app's URLSession (synchronous, on the plugin queue).
import json as _json
import _lumen
from _lumen_bridge import native


class RequestException(Exception):
    pass


class ConnectionError(RequestException):
    pass


class Timeout(RequestException):
    pass


class HTTPError(RequestException):
    pass


class exceptions:
    RequestException = RequestException
    ConnectionError = ConnectionError
    Timeout = Timeout
    HTTPError = HTTPError


class Response(object):
    def __init__(self, data, url):
        self.status_code = int(data.get("status", 0))
        self.headers = data.get("headers") or {}
        self.content = _lumen.b64decode(data.get("body") or "")
        self.url = data.get("url", url)
        self.ok = 200 <= self.status_code < 400
        self.encoding = "utf-8"
        self.reason = ""

    @property
    def text(self):
        try:
            return self.content.decode("utf-8")
        except Exception:
            return ""

    def json(self, **kwargs):
        return _json.loads(self.text)

    def raise_for_status(self):
        if not self.ok:
            raise HTTPError(str(self.status_code) + " for url " + self.url)


def request(method, url, params=None, data=None, json=None, headers=None, timeout=20, files=None, **kwargs):
    from urllib.parse import urlencode
    if params:
        url = url + ("&" if "?" in url else "?") + urlencode(params)
    headers = dict(headers or {})
    body = None
    if json is not None:
        body = _json.dumps(json).encode("utf-8")
        headers.setdefault("Content-Type", "application/json")
    elif isinstance(data, dict):
        body = urlencode(data).encode("utf-8")
        headers.setdefault("Content-Type", "application/x-www-form-urlencoded")
    elif isinstance(data, str):
        body = data.encode("utf-8")
    elif data is not None:
        body = bytes(data)
    if isinstance(timeout, (tuple, list)):
        timeout = timeout[-1]
    result = native("http", method=method.upper(), url=str(url), headers={str(k): str(v) for k, v in headers.items()},
                    body=None if body is None else _lumen.b64encode(body), timeout=float(timeout or 20))
    if result is None or result.get("error"):
        raise ConnectionError((result or {}).get("error") or "network error")
    return Response(result, url)


def get(url, params=None, **kwargs):
    return request("GET", url, params=params, **kwargs)


def post(url, data=None, json=None, **kwargs):
    return request("POST", url, data=data, json=json, **kwargs)


def put(url, data=None, **kwargs):
    return request("PUT", url, data=data, **kwargs)


def delete(url, **kwargs):
    return request("DELETE", url, **kwargs)


def head(url, **kwargs):
    return request("HEAD", url, **kwargs)


def patch(url, data=None, **kwargs):
    return request("PATCH", url, data=data, **kwargs)


class Session(object):
    def __init__(self):
        self.headers = {}

    def request(self, method, url, headers=None, **kwargs):
        merged = dict(self.headers)
        merged.update(headers or {})
        return request(method, url, headers=merged, **kwargs)

    def get(self, url, **kwargs):
        return self.request("GET", url, **kwargs)

    def post(self, url, **kwargs):
        return self.request("POST", url, **kwargs)

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False
