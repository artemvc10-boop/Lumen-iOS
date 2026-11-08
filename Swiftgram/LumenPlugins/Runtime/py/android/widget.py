# android.widget
from _lumen_views import (
    View, LinearLayout, FrameLayout, RelativeLayout, ScrollView,
    HorizontalScrollView, TextView, Button, EditText, ImageView,
)

# Layout params are the same across containers here; plugins use e.g.
# LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT). View.LayoutParams covers them.
LinearLayout.LayoutParams = View.LayoutParams
FrameLayout.LayoutParams = View.LayoutParams
RelativeLayout.LayoutParams = View.LayoutParams
ScrollView.LayoutParams = View.LayoutParams
FrameLayout.LayoutParams = View.LayoutParams


import _lumen_java
_lumen_java.fill_module(__name__)
