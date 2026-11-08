# abc: abstract classes without enforcement.


class ABCMeta(type):
    pass


class ABC(object):
    pass


def abstractmethod(fn):
    return fn


abstractproperty = property
abstractclassmethod = classmethod
abstractstaticmethod = staticmethod
