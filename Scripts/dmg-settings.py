"""Finder layout for the drag-to-Applications release disk image."""
import os

application = defines["app"]
files = [application, (defines["notices"], ".THIRD_PARTY_NOTICES.md")]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")
icon_locations = {"TCLimate.app": (140, 120), "Applications": (500, 120)}
background = "builtin-arrow"
window_rect = ((100, 100), (640, 280))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 14
format = "UDZO"
