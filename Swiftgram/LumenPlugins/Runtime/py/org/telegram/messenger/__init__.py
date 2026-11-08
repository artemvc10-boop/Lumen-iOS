# org.telegram.messenger — re-exported from a top-level module so other packages can import
# these names without Skulpt's relative-import quirk.
from _lumen_tg import (
    AndroidUtilities, Theme, R, FileLoader, LocaleController,
    UserConfig, ApplicationLoader, MediaController, MessagesController, Utilities,
)
from _lumen_java import JavaStub


def __getattr__(name):
    return JavaStub("messenger." + name)
