// Loads PipModel.js (a QML JavaScript library) in Node and checks its logic.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "..", "PipModel.js"), "utf8").replace(/^\.pragma library\n/, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox)
const M = sandbox.module.exports

const tests = []
const test = (name, fn) => tests.push([name, fn])
const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`)

test("settings default when missing or invalid", () => {
  const s = M.normalizeSettings({ hover: "explode", opacity: 9, shadow: "yes", animation: "calm", extra: 1 })
  assert.equal(s.hover, "grow")
  assert.equal(s.opacity, 1)
  assert.equal(s.shadow, true)
  assert.equal(s.animation, "calm")
  assert.equal(s.extra, undefined)
  assert.deepEqual(Object.keys(M.normalizeSettings(null)).sort(), Object.keys(M.DEFAULTS).sort())
})

test("cycling a setting wraps around its choices", () => {
  let s = M.normalizeSettings({ corner: "br" })
  s = M.cycleSetting(s, "corner")
  assert.equal(s.corner, "tl")
  for (let i = 0; i < 4; i++) s = M.cycleSetting(s, "corner")
  assert.equal(s.corner, "tl")
  assert.equal(M.cycleSetting(s, "opacity").opacity, s.opacity)
})

test("a region becomes a crop of what it was picked on", () => {
  const c = M.cropFromRect({ x: 150, y: 120, w: 100, h: 50 }, { x: 100, y: 100, w: 400, h: 200 })
  near(c.x, 0.125); near(c.y, 0.1); near(c.w, 0.25); near(c.h, 0.25)
  assert.ok(M.isFullCrop(M.cropFromRect({ x: 0, y: 0, w: 400, h: 200 }, { x: 0, y: 0, w: 400, h: 200 })))
})

test("a region hanging off the source is clipped to it", () => {
  const c = M.cropFromRect({ x: -50, y: 150, w: 200, h: 200 }, { x: 0, y: 0, w: 400, h: 200 })
  near(c.x, 0); near(c.w, 0.375); near(c.y, 0.75); near(c.h, 0.25)
})

test("crops never collapse or escape the source", () => {
  const c = M.normalizeCrop({ x: 2, y: -1, w: 0, h: 5 })
  assert.ok(c.x >= 0 && c.x + c.w <= 1 + 1e-9 && c.w > 0)
  assert.ok(c.y >= 0 && c.y + c.h <= 1 + 1e-9 && c.h > 0)
})

test("the crop layout fills the view with exactly the crop", () => {
  const crop = { x: 0.25, y: 0.5, w: 0.5, h: 0.25 }
  const l = M.cropLayout(crop, 200, 100)
  assert.equal(l.width, 400); assert.equal(l.height, 400)
  assert.equal(l.x, -100); assert.equal(l.y, -200)
})

test("the aspect ratio follows the cropped pixels", () => {
  near(M.cropAspect({ x: 0, y: 0, w: 1, h: 1 }, 1920, 1080), 16 / 9)
  near(M.cropAspect({ x: 0, y: 0, w: 0.5, h: 1 }, 1920, 1080), 8 / 9)
})

test("a thin strip keeps its true shape", () => {
  // htop's CPU meters: a strip far wider than 10:1 must not be squashed.
  const pip = M.normalizePip({ id: "a", kind: "window", address: "ab", aspect: 13.05, width: 700, x: 0, y: 0 })
  near(pip.aspect, 13.05)
  near(M.cropAspect({ x: 0.026, y: 0.034, w: 0.957, h: 0.1176 }, 845, 527), 0.957 * 845 / (0.1176 * 527))
})

test("a region inside one window follows that window", () => {
  const wins = [{ address: "a", x: 0, y: 0, w: 500, h: 500 }, { address: "b", x: 400, y: 0, w: 500, h: 500 }]
  assert.equal(M.attachRegion({ x: 10, y: 10, w: 100, h: 100 }, wins).address, "a")
  assert.equal(M.attachRegion({ x: 350, y: 10, w: 200, h: 100 }, wins), null)
  assert.equal(M.windowAt(wins, 450, 10).address, "a")
  assert.equal(M.windowAt(wins, 950, 10), null)
})

test("corners, clamping and snapping keep a PiP on screen", () => {
  const p = M.cornerPosition("br", 1920, 1080, 400, 225, 10, 0)
  assert.deepEqual({ x: p.x, y: p.y }, { x: 1510, y: 845 })
  const t = M.cornerPosition("tl", 1920, 1080, 400, 225, 10, 30)
  assert.deepEqual({ x: t.x, y: t.y }, { x: 10, y: 40 })
  const c = M.clampPosition(5000, -300, 400, 225, 1920, 1080)
  assert.ok(c.x <= 1920 - 48 && c.y === 0)
  const s = M.snapPosition(1500, 830, 400, 225, 1920, 1080, 10, 36, 0)
  assert.ok(s.snapped); assert.equal(s.x, 1510); assert.equal(s.y, 845)
  assert.equal(M.snapPosition(800, 400, 400, 225, 1920, 1080, 10, 36, 0).snapped, false)
})

test("a PiP from the state file is validated", () => {
  assert.equal(M.normalizePip({ id: "x", kind: "window", address: "zz" }), null)
  assert.equal(M.normalizePip({ id: "x", kind: "screen", monitor: "../etc" }), null)
  assert.equal(M.normalizePip({ id: "../x", kind: "screen", monitor: "DP-1" }), null)
  const p = M.normalizePip({ id: "p1", kind: "window", address: "0x5586ABCD", title: "a\u0000b\u001b", width: 1e9, opacity: 0 })
  assert.equal(p.address, "5586abcd")
  assert.equal(p.title, "a b ")
  assert.equal(p.width, 4096)
  assert.ok(p.opacity >= 0.15)
  assert.equal(p.sticky, true)
})

test("the state file is capped and deduplicated", () => {
  const pips = []
  for (let i = 0; i < 40; i++) pips.push({ id: "p" + (i % 20), kind: "screen", monitor: "DP-1" })
  const s = M.normalizeState({ pips })
  assert.equal(s.pips.length, M.MAX_PIPS)
  assert.equal(new Set(s.pips.map((p) => p.id)).size, s.pips.length)
  assert.equal(M.normalizeState("garbage").pips.length, 0)
})

test("visibility follows workspace, screen and dock", () => {
  const p = M.normalizePip({ id: "p", kind: "screen", monitor: "DP-1", screen: "DP-1", sticky: false, workspace: 3 })
  assert.equal(M.visibleOn(p, "DP-1", 3), true)
  assert.equal(M.visibleOn(p, "DP-1", 4), false)
  assert.equal(M.visibleOn(p, "HDMI-A-1", 3), false)
  assert.equal(M.visibleOn({ ...p, sticky: true }, "DP-1", 9), true)
  assert.equal(M.visibleOn({ ...p, docked: true }, "DP-1", 3), false)
})

test("updates go through validation", () => {
  const list = [M.normalizePip({ id: "p", kind: "screen", monitor: "DP-1" })]
  const next = M.updatePip(list, "p", { width: -5, docked: true })
  assert.equal(next[0].width, M.MIN_WIDTH)
  assert.equal(next[0].docked, true)
  assert.notEqual(next, list)
  assert.equal(M.removePip(next, "p").length, 0)
})

test("labels and glyphs exist for every choice shown", () => {
  for (const g of Object.values(M.GLYPHS)) assert.ok(typeof g === "string" && g.length > 0)
  assert.equal(M.pipLabel(M.normalizePip({ id: "p", kind: "screen", monitor: "DP-1", crop: { x: 0.1, y: 0, w: 0.5, h: 0.5 } })), "DP-1 · region")
})

test("every setting value and key has an English and Spanish label", () => {
  for (const lang of ["en", "es"]) {
    const cat = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "i18n", lang + ".json"), "utf8"))
    for (const key of Object.keys(M.DEFAULTS)) {
      assert.ok(cat["settings." + key], `${lang}: settings.${key}`)
      for (const v of M.CHOICES[key] || []) assert.ok(cat[`value.${key}.${v}`], `${lang}: value.${key}.${v}`)
    }
  }
})

let failed = 0
for (const [name, fn] of tests) {
  try { fn(); console.log("ok   " + name) } catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}
if (failed) { console.log(failed + " failed"); process.exit(1) }
