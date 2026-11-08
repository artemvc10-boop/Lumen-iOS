# exteraGram file_utils.
import os
from _lumen_bridge import native


def get_plugins_dir():
    return native("fs", action="pluginsDir")


def get_cache_dir():
    return native("fs", action="cacheDir")


def get_files_dir():
    return native("fs", action="filesDir")


def get_images_dir():
    return "/storage/emulated/0/Pictures"


def get_videos_dir():
    return "/storage/emulated/0/Movies"


def get_audios_dir():
    return "/storage/emulated/0/Music"


def get_documents_dir():
    return "/storage/emulated/0/Documents"


def ensure_dir_exists(path):
    if not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)
    return path


def list_dir(path, recursive=False, include_files=True, include_dirs=False, extensions=None, *args, **kwargs):
    result = []
    for name in os.listdir(path):
        full = os.path.join(path, name)
        is_dir = os.path.isdir(full)
        if (is_dir and include_dirs) or (not is_dir and include_files):
            if extensions is None or os.path.splitext(name)[1].lower() in extensions:
                result.append(full)
        if is_dir and recursive:
            result.extend(list_dir(full, True, include_files, include_dirs, extensions))
    return result


def read_file(path, *args, **kwargs):
    with open(path, "r") as f:
        return f.read()


def read_file_bytes(path, *args, **kwargs):
    with open(path, "rb") as f:
        return f.read()


def write_file(path, content, *args, **kwargs):
    with open(path, "w") as f:
        f.write(content)
    return True


def write_file_bytes(path, content, *args, **kwargs):
    with open(path, "wb") as f:
        f.write(content)
    return True


def delete_file(path, *args, **kwargs):
    if os.path.exists(path):
        os.remove(path)
        return True
    return False
