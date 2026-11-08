# urllib.request.urlopen over requests.
import requests as _requests


class Request(object):
    def __init__(self, url, data=None, headers=None, method=None, **kwargs):
        self.full_url = url
        self.data = data
        self.headers = dict(headers or {})
        self.method = method or ("POST" if data is not None else "GET")

    def add_header(self, key, value):
        self.headers[key] = value


class _Reply(object):
    def __init__(self, response):
        self._response = response
        self.status = response.status_code
        self.code = response.status_code
        self.headers = response.headers

    def read(self, *args):
        return self._response.content

    def getcode(self):
        return self.status

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def urlopen(url, data=None, timeout=20, *args, **kwargs):
    if isinstance(url, Request):
        response = _requests.request(url.method, url.full_url, data=url.data, headers=url.headers, timeout=timeout)
    else:
        response = _requests.request("POST" if data is not None else "GET", url, data=data, timeout=timeout)
    return _Reply(response)
