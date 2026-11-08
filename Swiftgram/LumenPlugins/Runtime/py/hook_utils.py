# exteraGram hook_utils. There are no Java classes on iOS: lookups find nothing.


def find_class(class_name, *args, **kwargs):
    return None


def get_private_field(obj, field_name, *args, **kwargs):
    return None


def set_private_field(obj, field_name, new_value, *args, **kwargs):
    return False


def get_static_private_field(cls, field_name, *args, **kwargs):
    return None


def set_static_private_field(cls, field_name, new_value, *args, **kwargs):
    return False
