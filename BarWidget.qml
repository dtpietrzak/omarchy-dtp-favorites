import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Favorites.js" as Favorites

// An icon on the bar for each favorite app, in the order they were starred.
// A click opens the app, or a new window of it, the way the app list does.
BarWidget {
  id: root
  moduleName: "io.github.dtpietrzak.favorites"

  readonly property color barForeground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property int gap: Style.space(2)

  // { id, name, icon, entry } for each favorite that is installed.
  property var entries: []

  // The square behind an icon, in the theme's accent: half strength under
  // the pointer, full while held down, and a quarter while the app it
  // launched is still starting.
  readonly property color accent: Commons.Color.accent
  readonly property color hoverFill: Qt.alpha(root.accent, 0.5)
  readonly property color pressFill: Qt.alpha(root.accent, 1)
  readonly property color loadingFill: Qt.alpha(root.accent, 0.25)
  readonly property int squareSize: Math.min(Style.bar.iconCanvas + Style.space(6), root.barSize - Style.space(2))

  // Launches still waiting for a window: id -> { started, before }, where
  // before is the windows that were already open.
  property var pending: ({})
  readonly property int launchTimeout: 15000

  implicitWidth: vertical ? barSize : icons.implicitWidth
  implicitHeight: vertical ? icons.implicitHeight : barSize

  FavoritesStore {
    id: store
    seedDefaults: true
    onAppsChanged: root.rebuild()
  }

  function rebuild() {
    var next = []
    var apps = store.apps || []
    for (var i = 0; i < apps.length; i++) {
      var entry = DesktopEntries.byId(apps[i])
      if (!entry) continue
      var name = String(entry.name || apps[i])
      if (name.length > 120) name = name.slice(0, 120) + "…"
      next.push({ id: apps[i], name: name, icon: String(entry.icon || ""), entry: entry })
    }
    root.entries = next
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (!value) value = "application-x-executable"
    if (value.charAt(0) === "/") return "file://" + value
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    var found = Quickshell.iconPath(value, true)
    if (found && String(found).length > 0) return found
    return Quickshell.iconPath("application-x-executable", true) || ""
  }

  // A command line from a desktop entry, without the field codes it leaves
  // for a launcher to fill in.
  function commandWords(command) {
    var words = []
    var list = command || []
    for (var i = 0; i < list.length; i++) {
      var word = String(list[i] || "")
      if (word && !/^%[a-zA-Z]$/.test(word)) words.push(Util.shellQuote(word))
    }
    return words
  }

  // The entry's standard "new-window" action, if it declares one.
  function newWindowAction(entry) {
    var actions = []
    try { actions = entry && entry.actions ? entry.actions : [] } catch (e) { actions = [] }
    for (var i = 0; i < actions.length; i++) {
      if (actions[i] && String(actions[i].id) === "new-window") return actions[i]
    }
    return null
  }

  // Every click opens a new window. A terminal app goes through Omarchy's TUI
  // launcher, as the shell's app library does. An app with a "new-window"
  // action runs that, since single-instance apps such as Files only raise the
  // window they already have when activated. Anything else goes through
  // gtk-launch, which needs the ".desktop" suffix. All run in their own scope
  // under uwsm.
  function launch(item) {
    if (!item || !item.id) return
    var entry = DesktopEntries.byId(item.id) || item.entry
    root.beginLoading(item.id)
    if (entry && entry.runInTerminal) {
      var tui = root.commandWords(entry.command)
      if (tui.length > 0) {
        Util.execDetached("omarchy-launch-tui " + tui.join(" "))
        return
      }
    }
    var action = root.newWindowAction(entry)
    var words = action ? root.commandWords(action.command) : []
    Util.execDetached(words.length > 0
      ? "uwsm-app -- " + words.join(" ")
      : "uwsm-app -- gtk-launch " + Util.shellQuote(item.id + ".desktop"))
  }

  function toplevels() {
    try { return ToplevelManager.toplevels.values || [] } catch (e) { return [] }
  }

  function setPending(next) {
    root.pending = next
    if (Object.keys(next).length > 0) { if (!expiry.running) expiry.start() }
    else expiry.stop()
  }

  function beginLoading(id) {
    var next = ({})
    for (var key in root.pending) next[key] = root.pending[key]
    next[id] = { started: Date.now(), before: root.toplevels().slice() }
    root.setPending(next)
  }

  function finishLoading(ids) {
    if (ids.length === 0) return
    var next = ({})
    for (var key in root.pending) if (ids.indexOf(key) < 0) next[key] = root.pending[key]
    root.setPending(next)
  }

  // The names a window of this app may carry as its app id: the desktop id,
  // its last part (org.gnome.Nautilus -> nautilus), the entry's
  // StartupWMClass, its command, and Omarchy's TUI launcher name.
  function windowNames(id) {
    var names = [String(id).toLowerCase()]
    var dot = String(id).lastIndexOf(".")
    if (dot >= 0) names.push(String(id).slice(dot + 1).toLowerCase())
    var entry = DesktopEntries.byId(id)
    if (entry) {
      var wmClass = String(entry.startupClass || "")
      if (wmClass && wmClass.indexOf("@@") < 0) names.push(wmClass.toLowerCase())
      var command = entry.command || []
      if (command.length > 0) {
        var program = String(command[0] || "")
        program = program.slice(program.lastIndexOf("/") + 1).toLowerCase()
        if (program) {
          names.push(program)
          names.push("org.omarchy." + program)
        }
      }
    }
    return names
  }

  function isWindowOf(toplevel, id) {
    var appId = String((toplevel && toplevel.appId) || "").toLowerCase()
    return appId.length > 0 && root.windowNames(id).indexOf(appId) >= 0
  }

  // A new window of the app ends its loading. A new window nobody claims
  // ends a lone launch too, for apps whose window id matches none of the
  // names above.
  function checkWindows() {
    var ids = Object.keys(root.pending)
    if (ids.length === 0) return
    var all = root.toplevels()
    var done = []
    var unclaimed = false
    for (var i = 0; i < all.length; i++) {
      var claimed = false
      for (var j = 0; j < ids.length; j++) {
        if (root.pending[ids[j]].before.indexOf(all[i]) >= 0) continue
        if (root.isWindowOf(all[i], ids[j])) {
          claimed = true
          if (done.indexOf(ids[j]) < 0) done.push(ids[j])
        }
      }
      var isNew = true
      for (var k = 0; k < ids.length; k++) {
        if (root.pending[ids[k]].before.indexOf(all[i]) >= 0) { isNew = false; break }
      }
      if (isNew && !claimed) unclaimed = true
    }
    if (unclaimed && ids.length === 1 && done.length === 0) done.push(ids[0])
    root.finishLoading(done)
  }

  // An app that only focuses its open window, instead of opening another,
  // is done once that window is in front.
  function checkActive() {
    var active = ToplevelManager.activeToplevel
    if (!active) return
    var done = []
    for (var id in root.pending) if (root.isWindowOf(active, id)) done.push(id)
    root.finishLoading(done)
  }

  Component.onCompleted: rebuild()

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.checkWindows() }
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() { root.checkActive() }
  }

  // A launch that never shows a window stops looking busy after a while.
  Timer {
    id: expiry
    interval: 1000
    repeat: true
    onTriggered: {
      var now = Date.now()
      var done = []
      for (var id in root.pending) if (now - root.pending[id].started > root.launchTimeout) done.push(id)
      root.finishLoading(done)
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuild() }
  }

  // The bar lays a press handler over every widget for rearranging the bar,
  // so a widget never sees its own presses or drags. This sits over that one,
  // on the icons, as workspace control's bar does for its numbers: a click
  // opens the app, and a drag along the row reorders the favorites. Moving
  // the widget itself is left to `omarchy bar move`.
  readonly property Item barSlot: {
    for (var item = root.parent; item; item = item.parent) {
      if ("widgetWidth" in item && "panelOpen" in item) return item
    }
    return null
  }

  // The icon being dragged along the row, and where it would land.
  property Item reorderButton: null
  property int reorderInsert: -1
  property point reorderPos: Qt.point(0, 0)
  property point reorderGrab: Qt.point(0, 0)
  property point reorderMarker: Qt.point(0, 0)

  // Ending a drag on the touchpad also sends a click at the drop point a
  // moment after the release, which must not open the app under it.
  property real droppedAt: 0
  function justDropped() { return Date.now() - droppedAt < 200 }

  function buttons() {
    var found = []
    for (var i = 0; i < iconRepeater.count; i++) {
      var item = iconRepeater.itemAt(i)
      if (item) found.push(item)
    }
    return found
  }

  // The icon at a point in the widget, gaps split between its neighbors.
  function buttonAt(point) {
    var all = buttons()
    var pad = root.gap / 2
    for (var i = 0; i < all.length; i++) {
      var at = root.mapFromItem(all[i], 0, 0)
      var padX = vertical ? 0 : pad
      var padY = vertical ? pad : 0
      if (point.x >= at.x - padX && point.x < at.x + all[i].width + padX
          && point.y >= at.y - padY && point.y < at.y + all[i].height + padY) return all[i]
    }
    return null
  }

  // The position in the row a point falls before.
  function insertIndexAt(point) {
    var all = buttons()
    for (var i = 0; i < all.length; i++) {
      var at = root.mapFromItem(all[i], 0, 0)
      var middle = vertical ? at.y + all[i].height / 2 : at.x + all[i].width / 2
      if ((vertical ? point.y : point.x) < middle) return i
    }
    return all.length
  }

  function updateReorder(point) {
    reorderPos = point
    var all = buttons()
    if (all.length === 0) return
    var index = insertIndexAt(point)
    reorderInsert = index
    var gap = root.gap / 2
    var anchor = index < all.length
      ? root.mapFromItem(all[index], 0, 0)
      : root.mapFromItem(all[all.length - 1], all[all.length - 1].width, all[all.length - 1].height)
    reorderMarker = vertical
      ? Qt.point(0, index < all.length ? anchor.y - gap : anchor.y + gap)
      : Qt.point(index < all.length ? anchor.x - gap : anchor.x + gap, 0)
  }

  function finishReorder() {
    var button = reorderButton
    var insert = reorderInsert
    reorderButton = null
    reorderInsert = -1
    if (!button) return
    droppedAt = Date.now()
    var all = buttons()
    var from = all.indexOf(button)
    var shown = all.map(function(item) { return item.modelData.id })
    var next = Favorites.reorder(store.apps, shown, from, insert)
    if (next !== null) store.save(next)
  }

  MouseArea {
    id: iconsDrag
    parent: root.barSlot || root
    z: 1000
    enabled: !!root.barSlot && root.entries.length > 0
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: pressed && root.reorderButton ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    property Item pressedButton: null
    property int pressedWith: Qt.NoButton
    property point pressPoint

    function inWidget(mouse) { return mapToItem(root, mouse.x, mouse.y) }

    onPressed: mouse => {
      pressPoint = Qt.point(mouse.x, mouse.y)
      pressedWith = mouse.button
      var point = inWidget(mouse)
      pressedButton = root.justDropped() ? null : root.buttonAt(point)
      if (!pressedButton) return
      pressedButton.heldButtons = mouse.button
      var at = root.mapFromItem(pressedButton, 0, 0)
      root.reorderGrab = Qt.point(point.x - at.x, point.y - at.y)
    }

    onPositionChanged: mouse => {
      if (!pressedButton || pressedWith !== Qt.LeftButton) return
      var dx = mouse.x - pressPoint.x
      var dy = mouse.y - pressPoint.y
      if (root.reorderButton !== pressedButton && dx * dx + dy * dy < 36) return
      if (root.reorderButton !== pressedButton) {
        pressedButton.heldButtons = Qt.NoButton
        pressedButton.hideOwnTooltip()
        root.reorderButton = pressedButton
      }
      root.updateReorder(inWidget(mouse))
    }

    onReleased: mouse => {
      var button = pressedButton
      pressedButton = null
      if (button) button.heldButtons = Qt.NoButton
      if (root.reorderButton) root.finishReorder()
      else if (button && root.buttonAt(inWidget(mouse)) === button) {
        button.hideOwnTooltip()
        root.launch(button.modelData)
      }
    }

    onCanceled: {
      if (pressedButton) pressedButton.heldButtons = Qt.NoButton
      pressedButton = null
      root.reorderButton = null
      root.reorderInsert = -1
    }
  }

  Grid {
    id: icons
    // Placed by value: an anchor cleared when the bar changes sides would
    // leave the icons where it last put them.
    x: root.vertical ? (root.width - width) / 2 : 0
    y: root.vertical ? 0 : (root.height - height) / 2
    columns: root.vertical ? 1 : Math.max(1, root.entries.length)
    spacing: root.gap

    Repeater {
      id: iconRepeater
      model: root.entries

      BarIconButton {
        id: button
        required property var modelData
        readonly property bool loading: root.pending[button.modelData.id] !== undefined
        // The bar's press handler, or ours above it, holds the button down.
        readonly property bool held: (button.heldButtons & (Qt.LeftButton | Qt.MiddleButton)) !== 0

        bar: root.bar
        text: ""
        // The app's own icon is drawn below.
        iconComponent: Component { Item {} }
        tooltipText: modelData.name
        // Without the bar's slot to lay the drag layer in, clicks come here.
        onPressed: function(b) {
          if (b === Qt.LeftButton || b === Qt.MiddleButton) root.launch(button.modelData)
        }

        Rectangle {
          anchors.centerIn: parent
          width: root.squareSize
          height: root.squareSize
          radius: Style.space(5)
          color: button.held ? root.pressFill
            : button.tooltipHovered && !root.reorderButton ? root.hoverFill
            : button.loading ? root.loadingFill
            : Qt.alpha(root.hoverFill, 0)
          Behavior on color { ColorAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
        }

        IconImage {
          anchors.centerIn: parent
          implicitSize: Style.bar.iconCanvas
          scale: button.pressScale
          source: root.iconSource(button.modelData.icon)
        }
      }
    }
  }

  // The icon following the pointer along the row.
  ShaderEffectSource {
    visible: !!root.reorderButton
    z: 20
    sourceItem: root.reorderButton
    width: root.reorderButton ? root.reorderButton.width : 0
    height: root.reorderButton ? root.reorderButton.height : 0
    x: root.vertical ? (root.width - width) / 2 : root.reorderPos.x - root.reorderGrab.x
    y: root.vertical ? root.reorderPos.y - root.reorderGrab.y : (root.height - height) / 2
    opacity: 0.8
  }

  // Where it would land.
  Rectangle {
    visible: !!root.reorderButton && root.reorderInsert >= 0
    z: 19
    x: root.vertical ? Math.round((root.width - width) / 2) : root.reorderMarker.x - width / 2
    y: root.vertical ? root.reorderMarker.y - height / 2 : Math.round((root.height - height) / 2)
    width: root.vertical ? Style.space(14) : 2
    height: root.vertical ? 2 : Style.space(14)
    radius: 1
    color: Commons.Color.accent
  }
}
