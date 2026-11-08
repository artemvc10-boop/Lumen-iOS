# java.util — collections as Python list/dict with the Java method names.


class ArrayList(list):
    def __init__(self, items=None, *args):
        list.__init__(self)
        if items is not None and not isinstance(items, int):
            for item in items:
                list.append(self, item)

    def add(self, *args):
        if len(args) == 2:
            self.insert(args[0], args[1])
        else:
            self.append(args[0])
        return True

    def addAll(self, items):
        for item in items:
            self.append(item)
        return True

    def get(self, index):
        return self[index]

    def set(self, index, value):
        old = self[index]
        self[index] = value
        return old

    def size(self):
        return len(self)

    def isEmpty(self):
        return len(self) == 0

    def contains(self, value):
        return value in self

    def indexOf(self, value):
        try:
            return self.index(value)
        except ValueError:
            return -1

    def toArray(self, *args):
        return list(self)


LinkedList = ArrayList


class HashMap(dict):
    def put(self, key, value):
        old = self.get(key)
        self[key] = value
        return old

    def containsKey(self, key):
        return key in self

    def containsValue(self, value):
        return value in self.values()

    def size(self):
        return len(self)

    def isEmpty(self):
        return len(self) == 0

    def keySet(self):
        return list(self.keys())

    def entrySet(self):
        return [_Entry(k, v) for k, v in self.items()]

    def getOrDefault(self, key, default):
        return self.get(key, default)

    def remove(self, key):
        return self.pop(key, None)


LinkedHashMap = HashMap
TreeMap = HashMap


class _Entry(object):
    def __init__(self, key, value):
        self._key = key
        self._value = value

    def getKey(self):
        return self._key

    def getValue(self):
        return self._value


class HashSet(set):
    def add(self, value):
        had = value in self
        set.add(self, value)
        return not had

    def contains(self, value):
        return value in self

    def size(self):
        return len(self)

    def isEmpty(self):
        return len(self) == 0


class Locale(object):
    def __init__(self, language="en", country=""):
        self._language = language
        self._country = country

    def getLanguage(self):
        return self._language

    def getCountry(self):
        return self._country

    def toString(self):
        return self._language + ("_" + self._country if self._country else "")

    @staticmethod
    def getDefault():
        from _lumen_bridge import native
        info = native("locale") or {}
        return Locale(info.get("language", "en"), info.get("country", ""))

    ENGLISH = None
    US = None


class Arrays(object):
    @staticmethod
    def asList(*items):
        if len(items) == 1 and isinstance(items[0], (list, tuple)):
            return ArrayList(items[0])
        return ArrayList(items)


class Collections(object):
    @staticmethod
    def emptyList():
        return ArrayList()

    @staticmethod
    def sort(items, *args):
        items.sort()


class UUID(object):
    @staticmethod
    def randomUUID():
        import uuid
        return uuid.uuid4()


import _lumen_java
_lumen_java.fill_module(__name__)
