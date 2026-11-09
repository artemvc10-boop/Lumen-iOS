# Asynchronous network calls: they never block the plugin queue.
#
#   from lumen import net
#   net.fetch("https://example.com/api", lambda r: print(r.status_code, r.json()))
#   net.download("https://example.com/a.jpg", "/abs/or/plugin/relative.jpg", lambda ok, path: ...)
import json as _json
import _lumen
from _lumen_bridge import native


class Response(object):
    def __init__(self, data):
        data = data or {}
        self.error = data.get("error")
        self.status_code = int(data.get("status", 0) or 0)
        self.headers = data.get("headers") or {}
        self.content = _lumen.b64decode(data.get("body") or "")
        self.ok = self.error is None and 200 <= self.status_code < 400

    @property
    def text(self):
        try:
            return self.content.decode("utf-8")
        except Exception:
            return ""

    def json(self):
        return _json.loads(self.text)


def fetch(url, callback=None, method="GET", headers=None, json=None, data=None, timeout=30):
    import _lumen_host
    headers = dict(headers or {})
    body = None
    if json is not None:
        body = _json.dumps(json).encode("utf-8")
        headers.setdefault("Content-Type", "application/json")
    elif isinstance(data, str):
        body = data.encode("utf-8")
    elif data is not None:
        body = bytes(data)
    callback_id = None
    if callback is not None:
        callback_id = _lumen_host.register_callback(lambda result: callback(Response(result)))
    native("httpAsync", method=method.upper(), url=str(url), headers={str(k): str(v) for k, v in headers.items()},
           body=None if body is None else _lumen.b64encode(body), timeout=float(timeout), callback=callback_id)


def download(url, path, callback=None, headers=None, timeout=60):
    import _lumen_host
    callback_id = None
    if callback is not None:
        callback_id = _lumen_host.register_callback(lambda result: callback(bool((result or {}).get("ok")), (result or {}).get("path")))
    native("download", url=str(url), path=str(path), headers={str(k): str(v) for k, v in (headers or {}).items()},
           timeout=float(timeout), callback=callback_id)
