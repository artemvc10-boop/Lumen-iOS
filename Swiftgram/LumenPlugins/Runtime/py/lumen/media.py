# Pick an image (or any file) from the system picker; callback(path) is called with the
# chosen file's path, or None if cancelled. Used by editors to choose a banner/background.
from _lumen_bridge import native

_next_code = [41000]


def pick(callback, mime="image/*"):
    import _lumen_activity
    code = _next_code[0]
    _next_code[0] += 1

    def deliver(path, _mime):
        callback(path)

    _lumen_activity.register_direct_result(code, deliver)
    native("pickMedia", requestCode=int(code), mime=mime or "*/*")
    return code
