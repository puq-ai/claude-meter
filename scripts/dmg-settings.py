"""dmgbuild settings for ClaudeMeter."""

volume_name = "ClaudeMeter"
format = "UDBZ"

files = [defines["APP_PATH"]]
symlinks = {"Applications": "/Applications"}

background_color = "#F5F5F7"
window_rect = ((200, 120), (480, 320))
icon_size = 80
text_size = 12
icon_locations = {
    "ClaudeMeter.app": (140, 140),
    "Applications": (340, 140),
}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
