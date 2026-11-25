.pragma library

// Pure logic for OmaPiP: settings, the shape of a PiP, geometry and crops.
// No QML types here, so tests/model.test.js can load it in Node.

var VERSION = 1

// Hard limits keep a hand-edited or corrupted state file from creating
// hundreds of live captures or windows larger than any screen.
var MAX_PIPS = 12
var MIN_WIDTH = 96
var MAX_WIDTH = 4096
var MIN_CROP = 0.01

// Nerd Font (Material Design) glyphs.
var GLYPHS = {
  pip: "\u{f0e57}",
  close: "\u{f0156}",
  pin: "\u{f0403}",
  pinOff: "\u{f0404}",
  dock: "\u{f0795}",
  undock: "\u{f0120}",
  eye: "\u{f0208}",
  eyeOff: "\u{f0209}",
  clickThrough: "\u{f037e}",
  focus: "\u{f03cc}",
  opacity: "\u{f05cc}",
  settings: "\u{f0493}",
  add: "\u{f0415}",
  monitor: "\u{f0379}",
  window: "\u{f08c6}",
  region: "\u{f019e}",
  crosshairs: "\u{f01a3}",
  resize: "\u{f045d}",
  ghost: "\u{f02a0}",
  next: "\u{f0142}",
  back: "\u{f0141}",
  animation: "\u{f05d8}",
  delete: "\u{f01b4}"
}

var SIZES = { small: 0.16, medium: 0.24, large: 0.34 }

var DEFAULTS = {
  visibility: "all",          // "all" workspaces, or the "workspace" a PiP was made on
  size: "medium",             // small | medium | large: starting width as a share of the screen
  corner: "br",               // tl | tr | bl | br: where a new PiP lands
  hover: "grow",              // grow | ghost | dodge | none
  hoverScale: 1.35,           // how much "grow" enlarges a PiP under the pointer
  opacity: 1.0,               // resting opacity of a PiP
  radius: -1,                 // corner radius in px; -1 follows the Hyprland rounding
  border: "gradient",         // gradient | accent | none
  shadow: true,
  animation: "extreme",       // calm | lively | extreme
  thumbs: true,               // show docked PiPs as live thumbnails next to the bar icon
  peek: true,                 // hovering a thumbnail opens a large live preview
  hideWhenSourceVisible: false,
  closeWhenSourceCloses: true,
  refresh: "live",            // live | 1 | 5 (seconds between frames)
  paintCursor: false,
  snap: true,                 // snap to screen edges and corners when dropped near them
  layer: "top",               // top | overlay (overlay also floats above fullscreen windows)
  background: "theme",        // theme | transparent: what shows through translucent windows
  leftClick: "panel",         // panel | pick | toggle
  middleClick: "toggle",
  rightClick: "pick"
}

var CHOICES = {
  visibility: ["all", "workspace"],
  size: ["small", "medium", "large"],
  corner: ["tl", "tr", "bl", "br"],
  hover: ["grow", "ghost", "dodge", "none"],
  border: ["gradient", "accent", "none"],
  animation: ["calm", "lively", "extreme"],
  refresh: ["live", "1", "5"],
  layer: ["top", "overlay"],
  background: ["theme", "transparent"],
  leftClick: ["panel", "pick", "toggle"],
  middleClick: ["panel", "pick", "toggle"],
  rightClick: ["panel", "pick", "toggle"]
}

var RANGES = {
  hoverScale: [1.05, 2.5],
  opacity: [0.15, 1.0],
  radius: [-1, 64]
}

var BOOLEANS = ["shadow", "thumbs", "peek", "hideWhenSourceVisible", "closeWhenSourceCloses", "paintCursor", "snap"]

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

// Every known key, each valid; unknown keys are dropped.
function normalizeSettings(raw) {
  var src = isObject(raw) ? raw : {}
  var out = {}
  for (var key in DEFAULTS) {
    var def = DEFAULTS[key]
    var v = src[key]
    if (CHOICES[key]) {
      v = String(v)
      out[key] = CHOICES[key].indexOf(v) >= 0 ? v : def
    } else if (RANGES[key]) {
      out[key] = clamp(num(v, def), RANGES[key][0], RANGES[key][1])
    } else if (BOOLEANS.indexOf(key) >= 0) {
      out[key] = typeof v === "boolean" ? v : def
    } else {
      out[key] = def
    }
  }
  return out
}

function settingChoices(key) {
  return CHOICES[key] ? CHOICES[key].slice() : []
}

// Next value in a key's list, wrapping; used by the panel's cycling rows.
function cycleSetting(settings, key) {
  var list = CHOICES[key]
  if (!list) return settings
  var next = {}
  for (var k in settings) next[k] = settings[k]
  var i = list.indexOf(String(settings[key]))
  next[key] = list[(i + 1) % list.length]
  return normalizeSettings(next)
}

// Animation multiplier for "how animated": calm keeps the shell's own feel.
function motion(animation) {
  if (animation === "calm") return { speed: 1.0, springy: false, flair: 0 }
  if (animation === "lively") return { speed: 1.25, springy: true, flair: 1 }
  return { speed: 1.6, springy: true, flair: 2 }
}

// ------------------------------------------------------------------ crops

function normalizeCrop(raw) {
  var c = isObject(raw) ? raw : {}
  var x = clamp(num(c.x, 0), 0, 1 - MIN_CROP)
  var y = clamp(num(c.y, 0), 0, 1 - MIN_CROP)
  var w = clamp(num(c.w, 1), MIN_CROP, 1 - x)
  var h = clamp(num(c.h, 1), MIN_CROP, 1 - y)
  return { x: x, y: y, w: w, h: h }
}

function isFullCrop(c) {
  return c.x <= 0.0005 && c.y <= 0.0005 && c.w >= 0.9995 && c.h >= 0.9995
}

// A picked rectangle in global logical coordinates, relative to the
// rectangle of what it was picked on, as fractions of it.
function cropFromRect(rect, area) {
  if (!area || area.w <= 0 || area.h <= 0) return normalizeCrop(null)
  var x0 = clamp(rect.x, area.x, area.x + area.w)
  var y0 = clamp(rect.y, area.y, area.y + area.h)
  var x1 = clamp(rect.x + rect.w, area.x, area.x + area.w)
  var y1 = clamp(rect.y + rect.h, area.y, area.y + area.h)
  return normalizeCrop({
    x: (x0 - area.x) / area.w,
    y: (y0 - area.y) / area.h,
    w: (x1 - x0) / area.w,
    h: (y1 - y0) / area.h
  })
}

// The aspect ratio of a crop of a source of a given size.
function cropAspect(crop, sourceW, sourceH) {
  var w = Math.max(1, num(sourceW, 16)) * crop.w
  var h = Math.max(1, num(sourceH, 9)) * crop.h
  return clamp(w / h, 0.1, 10)
}

// Where the whole source must sit, and how large, so that the crop fills a
// view of viewW x viewH exactly.
function cropLayout(crop, viewW, viewH) {
  var fullW = viewW / crop.w
  var fullH = viewH / crop.h
  return { x: -crop.x * fullW, y: -crop.y * fullH, width: fullW, height: fullH }
}

// --------------------------------------------------------------- geometry

function rectContains(outer, inner) {
  return inner.x >= outer.x - 1 && inner.y >= outer.y - 1
    && inner.x + inner.w <= outer.x + outer.w + 1
    && inner.y + inner.h <= outer.y + outer.h + 1
}

function area(r) {
  return Math.max(0, r.w) * Math.max(0, r.h)
}

function intersection(a, b) {
  var x0 = Math.max(a.x, b.x)
  var y0 = Math.max(a.y, b.y)
  var x1 = Math.min(a.x + a.w, b.x + b.w)
  var y1 = Math.min(a.y + a.h, b.y + b.h)
  return { x: x0, y: y0, w: Math.max(0, x1 - x0), h: Math.max(0, y1 - y0) }
}

// The topmost window (first in the list) under a point.
function windowAt(windows, px, py) {
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (px >= w.x && py >= w.y && px < w.x + w.w && py < w.y + w.h) return w
  }
  return null
}

// What a dragged region is attached to: the window that holds (nearly) all of
// it, so the PiP follows that window everywhere, or else the screen itself.
function attachRegion(rect, windows) {
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    var overlap = area(intersection(rect, w))
    if (overlap > 0 && overlap >= area(rect) * 0.92) return w
    if (overlap > 0) return null
  }
  return null
}

function startWidth(sizeKey, screenW) {
  var share = SIZES[sizeKey] || SIZES.medium
  return Math.round(clamp(screenW * share, MIN_WIDTH, MAX_WIDTH))
}

// Top-left position of a w x h PiP in a corner of a screen, clear of a margin.
function cornerPosition(corner, screenW, screenH, w, h, margin, topInset) {
  var m = margin
  var top = m + (topInset || 0)
  var left = corner === "tl" || corner === "bl"
  var upper = corner === "tl" || corner === "tr"
  return {
    x: Math.round(left ? m : screenW - w - m),
    y: Math.round(upper ? top : screenH - h - m)
  }
}

// Keep at least part of a PiP reachable on screen.
function clampPosition(x, y, w, h, screenW, screenH) {
  var keep = Math.min(48, w / 2, h / 2)
  return {
    x: Math.round(clamp(x, keep - w, screenW - keep)),
    y: Math.round(clamp(y, 0, screenH - keep))
  }
}

// Snap to edges, and to corners where both edges are near.
function snapPosition(x, y, w, h, screenW, screenH, margin, threshold, topInset) {
  var top = margin + (topInset || 0)
  var out = { x: x, y: y, snapped: false }
  if (Math.abs(x - margin) < threshold) { out.x = margin; out.snapped = true }
  else if (Math.abs(x + w - (screenW - margin)) < threshold) { out.x = screenW - margin - w; out.snapped = true }
  if (Math.abs(y - top) < threshold) { out.y = top; out.snapped = true }
  else if (Math.abs(y + h - (screenH - margin)) < threshold) { out.y = screenH - margin - h; out.snapped = true }
  out.x = Math.round(out.x)
  out.y = Math.round(out.y)
  return out
}

// ------------------------------------------------------------------- PiPs

function cleanText(v, max) {
  // Control characters out, length bounded. Display sites use PlainText too.
  return String(v === undefined || v === null ? "" : v).replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, max || 120)
}

function cleanAddress(v) {
  var s = String(v || "").toLowerCase().replace(/^0x/, "")
  return /^[0-9a-f]{1,16}$/.test(s) ? s : ""
}

function cleanName(v) {
  var s = String(v || "")
  return /^[A-Za-z0-9._:-]{1,64}$/.test(s) ? s : ""
}

// A valid PiP or null. Positions are logical pixels on `screen`.
function normalizePip(raw) {
  if (!isObject(raw)) return null
  var kind = raw.kind === "window" || raw.kind === "screen" ? raw.kind : ""
  if (!kind) return null
  var id = /^[A-Za-z0-9-]{1,40}$/.test(String(raw.id || "")) ? String(raw.id) : ""
  if (!id) return null
  var address = kind === "window" ? cleanAddress(raw.address) : ""
  var monitor = kind === "screen" ? cleanName(raw.monitor) : ""
  if (kind === "window" && !address) return null
  if (kind === "screen" && !monitor) return null
  var refresh = CHOICES.refresh.indexOf(String(raw.refresh)) >= 0 ? String(raw.refresh) : ""
  var ws = Math.round(num(raw.workspace, 0))
  return {
    id: id,
    kind: kind,
    address: address,
    monitor: monitor,
    appId: cleanText(raw.appId, 80),
    title: cleanText(raw.title, 120),
    crop: normalizeCrop(raw.crop),
    screen: cleanName(raw.screen),
    x: Math.round(num(raw.x, 0)),
    y: Math.round(num(raw.y, 0)),
    width: Math.round(clamp(num(raw.width, 320), MIN_WIDTH, MAX_WIDTH)),
    aspect: clamp(num(raw.aspect, 16 / 9), 0.1, 10),
    opacity: clamp(num(raw.opacity, 1), RANGES.opacity[0], 1),
    sticky: raw.sticky !== false,
    workspace: ws,
    docked: raw.docked === true,
    clickThrough: raw.clickThrough === true,
    refresh: refresh,
    createdAt: Math.round(num(raw.createdAt, 0))
  }
}

function normalizeState(raw) {
  var src = isObject(raw) ? raw : {}
  var list = Array.isArray(src.pips) ? src.pips : []
  var seen = {}
  var pips = []
  for (var i = 0; i < list.length && pips.length < MAX_PIPS; i++) {
    var p = normalizePip(list[i])
    if (!p || seen[p.id]) continue
    seen[p.id] = true
    pips.push(p)
  }
  return { version: VERSION, pips: pips }
}

function newId(now, counter) {
  return "p" + Math.round(now).toString(36) + "-" + (counter % 1296).toString(36)
}

function pipLabel(p) {
  if (!p) return ""
  if (p.kind === "screen") return p.monitor + (isFullCrop(p.crop) ? "" : " · region")
  var base = p.title || p.appId || "Window"
  return isFullCrop(p.crop) ? base : base + " · region"
}

// Whether a PiP shows on a screen whose active workspace is `workspaceId`.
function visibleOn(p, screenName, workspaceId) {
  if (!p || p.docked) return false
  if (p.screen && screenName && p.screen !== screenName) return false
  return p.sticky || p.workspace === workspaceId
}

// Replace one PiP in a list by id, returning a new list.
function updatePip(pips, id, patch) {
  var out = []
  for (var i = 0; i < pips.length; i++) {
    if (pips[i].id !== id) { out.push(pips[i]); continue }
    var next = {}
    for (var k in pips[i]) next[k] = pips[i][k]
    for (var key in patch) next[key] = patch[key]
    var clean = normalizePip(next)
    out.push(clean || pips[i])
  }
  return out
}

function removePip(pips, id) {
  return pips.filter(function(p) { return p.id !== id })
}

function findPip(pips, id) {
  for (var i = 0; i < pips.length; i++) if (pips[i].id === id) return pips[i]
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    VERSION: VERSION, GLYPHS: GLYPHS, MAX_PIPS: MAX_PIPS, MIN_WIDTH: MIN_WIDTH, DEFAULTS: DEFAULTS, CHOICES: CHOICES,
    normalizeSettings: normalizeSettings, settingChoices: settingChoices, cycleSetting: cycleSetting,
    motion: motion, normalizeCrop: normalizeCrop, isFullCrop: isFullCrop, cropFromRect: cropFromRect,
    cropAspect: cropAspect, cropLayout: cropLayout, rectContains: rectContains, intersection: intersection,
    windowAt: windowAt, attachRegion: attachRegion, startWidth: startWidth, cornerPosition: cornerPosition,
    clampPosition: clampPosition, snapPosition: snapPosition, cleanText: cleanText, cleanAddress: cleanAddress,
    normalizePip: normalizePip, normalizeState: normalizeState, newId: newId, pipLabel: pipLabel,
    visibleOn: visibleOn, updatePip: updatePip, removePip: removePip, findPip: findPip
  }
}
