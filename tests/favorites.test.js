const assert = require("assert")
const fs = require("fs")
const path = require("path")
const Favorites = require("../Favorites.js")

// Ids stay exactly as DesktopEntries reports them.
assert.strictEqual(Favorites.appId("org.telegram.desktop"), "org.telegram.desktop")
assert.strictEqual(Favorites.appId(" chromium "), "chromium")
assert.strictEqual(Favorites.appId("bad\nid"), "")
assert.strictEqual(Favorites.appId("../etc/passwd"), "")
assert.strictEqual(Favorites.appId("x".repeat(257)), "")
assert.strictEqual(Favorites.appId(null), "")

// xdg-terminal-exec --print-id output.
assert.strictEqual(Favorites.idFromDesktopFile("com.mitchellh.ghostty.desktop\n"), "com.mitchellh.ghostty")
assert.strictEqual(Favorites.idFromDesktopFile("foot.desktop:new-window"), "foot")
assert.strictEqual(Favorites.idFromDesktopFile("org.telegram.desktop.desktop"), "org.telegram.desktop")
assert.strictEqual(Favorites.idFromDesktopFile(""), "")

assert.deepStrictEqual(Favorites.defaults("com.mitchellh.ghostty"), ["org.gnome.Nautilus", "chromium", "com.mitchellh.ghostty"])
assert.deepStrictEqual(Favorites.defaults(""), ["org.gnome.Nautilus", "chromium"])
assert.deepStrictEqual(Favorites.defaults("chromium"), ["org.gnome.Nautilus", "chromium"])

// Bad JSON never replaces the list.
assert.strictEqual(Favorites.parse("{"), null)
assert.strictEqual(Favorites.parse("\"x\""), null)
assert.strictEqual(Favorites.parse("{}"), null)
assert.deepStrictEqual(Favorites.parse('{"version":1,"apps":["a","a",3,"","b\\nc","d"]}'), ["a", "3", "d"])
assert.deepStrictEqual(Favorites.parse('["x"]'), ["x"])
assert.deepStrictEqual(Favorites.parse('{"apps":[]}'), [])

const many = Array.from({ length: 100 }, (_, i) => "app" + i)
assert.strictEqual(Favorites.clean(many).length, Favorites.LIMIT)

assert.deepStrictEqual(Favorites.toggle(["a", "b"], "c"), ["a", "b", "c"])
assert.deepStrictEqual(Favorites.toggle(["a", "b", "c"], "b"), ["a", "c"])
assert.strictEqual(Favorites.toggle(["a"], "bad\nid"), null)

const rows = [{ id: "a" }, { id: "b" }, { id: "c" }, { id: "d" }, { id: "" }]
assert.deepStrictEqual(
  Favorites.favoritesFirst(rows, r => r.id, Favorites.toMap(["d", "b"])).map(r => r.id),
  ["b", "d", "a", "c", ""]
)
assert.deepStrictEqual(Favorites.favoritesFirst(rows, r => r.id, {}).map(r => r.id), ["a", "b", "c", "d", ""])
assert.deepStrictEqual(Favorites.favoritesFirst(null, r => r, {}), [])
// Inherited keys never count as favorites.
assert.deepStrictEqual(Favorites.favoritesFirst([{ id: "toString" }], r => r.id, {}).map(r => r.id), ["toString"])

// Dragging on the bar.
assert.deepStrictEqual(Favorites.reorder(["a", "b", "c"], ["a", "b", "c"], 0, 3), ["b", "c", "a"])
assert.deepStrictEqual(Favorites.reorder(["a", "b", "c"], ["a", "b", "c"], 2, 0), ["c", "a", "b"])
assert.deepStrictEqual(Favorites.reorder(["a", "b", "c"], ["a", "b", "c"], 0, 2), ["b", "a", "c"])
assert.strictEqual(Favorites.reorder(["a", "b", "c"], ["a", "b", "c"], 1, 1), null)
assert.strictEqual(Favorites.reorder(["a", "b", "c"], ["a", "b", "c"], 1, 2), null)
assert.strictEqual(Favorites.reorder(["a", "b"], ["a", "b"], 5, 0), null)
assert.strictEqual(Favorites.reorder(["a", "b"], ["a", "b"], 0, 9), null)
// "x" is not installed, so the bar skips it; it keeps its slot in the file.
assert.deepStrictEqual(Favorites.reorder(["a", "x", "b", "c"], ["a", "b", "c"], 2, 0), ["c", "x", "a", "b"])
// An icon whose favorite was removed meanwhile is not written back, and the
// one that was dragged is still the one that moves.
assert.deepStrictEqual(Favorites.reorder(["a", "c"], ["a", "b", "c"], 2, 0), ["c", "a"])
assert.deepStrictEqual(Favorites.reorder(["a", "c"], ["a", "b", "c"], 0, 3), ["c", "a"])
assert.strictEqual(Favorites.reorder(["a", "c"], ["a", "b", "c"], 1, 0), null)

const round = Favorites.parse(Favorites.serialize(["x", "y"]))
assert.deepStrictEqual(round, ["x", "y"])
assert.deepStrictEqual(JSON.parse(Favorites.serialize(["x"])), { version: 1, apps: ["x"] })
assert.deepStrictEqual(Favorites.toMap(["a", "b"]), { a: true, b: true })

// The app list and the menu ship byte-identical copies of the shared files.
const root = path.join(__dirname, "..")
const consumers = ["omarchy-dtp-app-list", "omarchy-dtp-menu", "omarchy-dtp-workspace-control"]
for (const repo of consumers) {
  for (const file of ["Favorites.js", "FavoritesStore.qml"]) {
    const copy = path.join(root, "..", repo, file)
    if (!fs.existsSync(copy)) continue
    assert.strictEqual(fs.readFileSync(copy, "utf8"), fs.readFileSync(path.join(root, file), "utf8"), repo + "/" + file + " differs")
  }
}
// The star lives only in the launchers; their copies match each other.
const stars = consumers.map(repo => path.join(root, "..", repo, "Star.qml")).filter(fs.existsSync)
for (const star of stars.slice(1)) {
  assert.strictEqual(fs.readFileSync(star, "utf8"), fs.readFileSync(stars[0], "utf8"), star + " differs")
}

// App names reach the bar tooltip, which is plain text, and nothing else.
const widget = fs.readFileSync(path.join(root, "BarWidget.qml"), "utf8")
assert.ok(!/\bText\s*\{/.test(widget), "BarWidget draws no Text of its own")

console.log("ok - favorites")
