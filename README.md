# omarchy-dtp-favorites

Your favorite apps as icons in the middle of the Omarchy bar. Click one to open a new window of the app. Apps that declare a `new-window` desktop action (Files, Chromium, Ghostty and most others) run that action, so single-instance apps like Files open another window instead of only raising the one they have; other apps launch the way the app list launches them.

Drag an icon along the bar to reorder the favorites, the way workspace control's numbers are reordered: a faded copy follows the pointer and an accent line shows where it will land. The order is saved to the favorites file. The icons take the bar's own press-and-drag, so move the widget itself with `omarchy bar move io.github.dtpietrzak.favorites --section <section>`.

Under the pointer an icon gets a rounded square in the theme's accent color at 50% opacity, 100% while the button is held. After a click the square stays at 25% until a window of the app opens or comes to the front, or for 15 seconds if none does.

Each row in the [DTP app list](https://github.com/dtpietrzak/omarchy-dtp-app-list), in the apps of the [DTP menu](https://github.com/dtpietrzak/omarchy-dtp-menu) (Super+Space), and in [workspace control](https://github.com/dtpietrzak/omarchy-dtp-workspace-control)'s app list and panel search has a star on the right. It is faded grey, turns white under the pointer, and turns gold when you click it, which adds the app to the bar. Click a gold star to take the app off again.

The shell plugin id is `io.github.dtpietrzak.favorites`.

## Where favorites live

`~/.config/omarchy/favorites.json`, shared by the bar, the app list and the menu:

```json
{ "version": 1, "apps": ["org.gnome.Nautilus", "chromium", "com.mitchellh.ghostty"] }
```

The ids are desktop entry names without `.desktop`, in the order shown on the bar (a newly starred app goes on the end). When the file does not exist the first plugin to load writes the defaults: Files, Chromium and your default terminal (`xdg-terminal-exec --print-id`, which is what `omarchy default terminal` sets). Delete the file to get the defaults back. An app that is not installed is kept in the file but not shown.

## Install

```bash
omarchy plugin add https://github.com/dtpietrzak/omarchy-dtp-favorites.git
omarchy plugin enable io.github.dtpietrzak.favorites --section center
```

`omarchy-dtp-install` does both for you.

## Check

```bash
node tests/favorites.test.js
omarchy plugin validate .
```

`Favorites.js` and `FavoritesStore.qml` are copied byte for byte into the app list, menu and workspace control repos, and `Star.qml` is shared by those three; the test fails if a checkout beside this one has a different copy.
