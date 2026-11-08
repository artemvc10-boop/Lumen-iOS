# typing: annotations only, nothing is checked.


class _Alias(object):
    def __init__(self, name):
        self._name = name

    def __getitem__(self, item):
        return self

    def __call__(self, *args, **kwargs):
        if args:
            return args[0]
        return None

    def __or__(self, other):
        return self

    def __ror__(self, other):
        return self

    def __repr__(self):
        return "typing." + self._name


Any = _Alias("Any")
List = _Alias("List")
Dict = _Alias("Dict")
Set = _Alias("Set")
FrozenSet = _Alias("FrozenSet")
Tuple = _Alias("Tuple")
Optional = _Alias("Optional")
Union = _Alias("Union")
Callable = _Alias("Callable")
Iterable = _Alias("Iterable")
Iterator = _Alias("Iterator")
Generator = _Alias("Generator")
Sequence = _Alias("Sequence")
Mapping = _Alias("Mapping")
MutableMapping = _Alias("MutableMapping")
Type = _Alias("Type")
Literal = _Alias("Literal")
Final = _Alias("Final")
ClassVar = _Alias("ClassVar")
Awaitable = _Alias("Awaitable")
Coroutine = _Alias("Coroutine")
NoReturn = _Alias("NoReturn")
Annotated = _Alias("Annotated")
TypeAlias = _Alias("TypeAlias")
Self = _Alias("Self")
TYPE_CHECKING = False


def TypeVar(name, *args, **kwargs):
    return _Alias(name)


def NewType(name, tp):
    return tp


def cast(tp, value):
    return value


def overload(fn):
    return fn


def final(fn):
    return fn


def runtime_checkable(cls):
    return cls


def get_type_hints(obj, *args, **kwargs):
    return {}


class Protocol(object):
    pass


class Generic(object):
    def __class_getitem__(cls, item):
        return cls


class NamedTuple(tuple):
    pass


class TypedDict(dict):
    pass
