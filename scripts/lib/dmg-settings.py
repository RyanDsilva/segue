# dmgbuild settings for the Developer ID DMGs (scripts/dmg.sh, docs/release/decisions.md
# R200). dmgbuild (MIT, pinned in scripts/dmg.sh) writes the window layout's .DS_Store
# itself, so no Finder or AppleScript is involved and the build runs headless.
#
# Defines (dmgbuild -D): app = path to the signed Segue.app; notice = optional path to a
# text file placed beside it (the Personal flavour's "owner only" note); icon = optional
# .icns for the volume.
#
# The window: Segue.app on the left, an Applications alias on the right, nothing else
# visible. No background image, so Finder draws its own window colour and the icon labels
# stay readable in both light and dark appearance.
import os.path

application = defines["app"]  # noqa: F821 (dmgbuild injects `defines`)
notice = defines.get("notice")  # noqa: F821
app_name = os.path.basename(application)

format = "ULMO"  # LZMA: smallest download, opens on every supported macOS
filesystem = "APFS"
size = None  # dmgbuild sizes the image from its contents

files = [application]
symlinks = {"Applications": "/Applications"}
icon_locations = {app_name: (160, 140), "Applications": (480, 140)}
if notice:
    files.append(notice)
    icon_locations[os.path.basename(notice)] = (320, 320)

window_rect = ((200, 160), (640, 480 if notice else 320))
default_view = "icon-view"
icon = defines.get("icon")  # noqa: F821 (the volume icon: the app's own .icns)
icon_size = 128
text_size = 13
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_list_view_settings = False
hide_extensions = [app_name]
