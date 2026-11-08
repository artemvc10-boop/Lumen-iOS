# Stand-ins for Java/Android classes, which do not exist on iOS.
#
# A JavaStub accepts any attribute access, call, index or arithmetic and returns another
# stub. It is falsy, so the common plugin pattern `cls = find_class(...); if not cls: return`
# skips Android-only code instead of crashing.

import _lumen

_names = {}


class JavaStub(object):
    def __init__(self, name="java", *args, **kwargs):
        if not isinstance(name, str):
            name = "java"
        object.__setattr__(self, "_stub_name", name)

    def __getattr__(self, key):
        if key.startswith("__") and key.endswith("__"):
            raise AttributeError(key)
        return JavaStub(self._stub_name + "." + key)

    def __setattr__(self, key, value):
        pass

    def __call__(self, *args, **kwargs):
        return JavaStub(self._stub_name + "()")

    def __bool__(self):
        return False

    def __len__(self):
        return 0

    def __iter__(self):
        return iter(())

    def __contains__(self, item):
        return False

    def __int__(self):
        return 0

    def __float__(self):
        return 0.0

    def __index__(self):
        return 0

    def __str__(self):
        return ""

    def __repr__(self):
        return "<Android " + self._stub_name + ">"

    def __getitem__(self, key):
        return JavaStub(self._stub_name + "[]")

    def __setitem__(self, key, value):
        pass

    def __eq__(self, other):
        return self is other

    def __ne__(self, other):
        return self is not other

    def __hash__(self):
        return id(self)

    def __lt__(self, other):
        return False

    def __gt__(self, other):
        return False

    def __le__(self, other):
        return False

    def __ge__(self, other):
        return False

    def __add__(self, other):
        return other

    def __radd__(self, other):
        return other

    def __sub__(self, other):
        return self

    def __rsub__(self, other):
        return other

    def __mul__(self, other):
        return self

    def __rmul__(self, other):
        return self

    def __truediv__(self, other):
        return self

    def __rtruediv__(self, other):
        return self

    def __floordiv__(self, other):
        return self

    def __rfloordiv__(self, other):
        return self

    def __mod__(self, other):
        return self

    def __or__(self, other):
        return other

    def __ror__(self, other):
        return other

    def __and__(self, other):
        return self

    def __rand__(self, other):
        return self

    def __neg__(self):
        return self

    def __invert__(self):
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def register_names(module, names):
    known = _names.get(module)
    if known is None:
        known = set()
        _names[module] = known
    for name in names:
        known.add(name)


def fill_module(module_name):
    """Gives the stub module `module_name` every name plugins import from it."""
    import sys
    target = sys.modules.get(module_name)
    if target is None:
        return
    for name in _names.get(module_name, ()):
        if not hasattr(target, name):
            setattr(target, name, JavaStub(module_name + "." + name))


def scan_imports(source):
    """Records names imported from stub packages so their modules can provide them."""
    import re
    flat = re.sub(r"\(\s*([^)]*)\)", lambda m: m.group(1).replace("\n", " "), source)
    for match in re.finditer(r"^[ \t]*from[ \t]+([A-Za-z_][\w.]*)[ \t]+import[ \t]+([^\n#]+)", flat, re.M):
        module = match.group(1)
        names = []
        for part in match.group(2).split(","):
            part = part.strip().strip("\\").strip()
            if not part or part == "*":
                continue
            names.append(part.split(" as ")[0].strip())
        register_names(module, names)
        _lumen.register_package(module)
        fill_module(module)
    for match in re.finditer(r"^[ \t]*import[ \t]+([^\n#]+)", flat, re.M):
        for part in match.group(1).split(","):
            module = part.strip().split(" as ")[0].strip()
            pieces = module.split(".")
            _lumen.register_package(module)
            for i in range(1, len(pieces)):
                register_names(".".join(pieces[:i]), [pieces[i]])
