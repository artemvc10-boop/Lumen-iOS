# org.telegram.tgnet — TL objects (TLRPC.TL_*), re-exported from a top-level module so other
# packages can import them without Skulpt's relative-import quirk.
from _lumen_tl import TLRPC, TLObject, TL_error


import _lumen_java
_lumen_java.fill_module(__name__)
