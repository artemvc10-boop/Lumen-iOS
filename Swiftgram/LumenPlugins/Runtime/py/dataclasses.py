# dataclasses, simplified: generates __init__ and __repr__ from annotations.

MISSING = object()


class _Field(object):
    def __init__(self, default=MISSING, default_factory=MISSING):
        self.default = default
        self.default_factory = default_factory


def field(default=MISSING, default_factory=MISSING, **kwargs):
    return _Field(default, default_factory)


def _process(cls):
    names = list(getattr(cls, "__annotations__", {}).keys())
    defaults = {}
    for name in names:
        if name in cls.__dict__:
            defaults[name] = cls.__dict__[name]

    def __init__(self, *args, **kwargs):
        for i, name in enumerate(names):
            if i < len(args):
                value = args[i]
            elif name in kwargs:
                value = kwargs[name]
            elif name in defaults:
                value = defaults[name]
                if isinstance(value, _Field):
                    if value.default_factory is not MISSING:
                        value = value.default_factory()
                    else:
                        value = value.default
            else:
                raise TypeError("missing argument: " + name)
            setattr(self, name, value)
        post = getattr(self, "__post_init__", None)
        if post is not None:
            post()

    def __repr__(self):
        return cls.__name__ + "(" + ", ".join(n + "=" + repr(getattr(self, n)) for n in names) + ")"

    def __eq__(self, other):
        return type(other) is type(self) and all(getattr(self, n) == getattr(other, n) for n in names)

    cls.__init__ = __init__
    cls.__repr__ = __repr__
    cls.__eq__ = __eq__
    cls.__dataclass_fields__ = names
    return cls


def dataclass(cls=None, **kwargs):
    if cls is None:
        return _process
    return _process(cls)


def asdict(obj):
    return {n: getattr(obj, n) for n in getattr(obj, "__dataclass_fields__", [])}


def astuple(obj):
    return tuple(getattr(obj, n) for n in getattr(obj, "__dataclass_fields__", []))


def is_dataclass(obj):
    return hasattr(obj, "__dataclass_fields__")
