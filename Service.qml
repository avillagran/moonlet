import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "PipModel.js" as Model

// OmaPiP: live picture-in-picture of any window or screen region.
//
// Owns the PiPs and their settings, follows Hyprland's windows, hosts one
// transparent layer per monitor for the floating PiPs, the picker, and the
// peek preview that grows out of a docked PiP's bar thumbnail. The bar widget
// reads and drives everything through this service.
//
// Captures stay inside the shell: nothing is recorded, saved or sent anywhere.
// Settings and the list of PiPs are the only files written.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.avillagran.omapip"
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/omapip/settings.json"
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omapip/pips.json"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  readonly property alias strings: strings

  // ------------------------------------------------------------- state
  property var settings: Model.normalizeSettings({})
  readonly property var motion: Model.motion(settings.animation)
  property var pips: []
  property bool stateLoaded: false
  property int idCounter: 0

  // Transient: where a new PiP flies in from, per id (screen-local rect).
  property var spawnRects: ({})

  // Bar widgets (one per bar, so one per monitor) tell us where they sit,
  // so PiPs can fly into the icon and out of their thumbnails.
  property var dockWidgets: []
  function registerDock(widget) {
    if (dockWidgets.indexOf(widget) < 0) dockWidgets = dockWidgets.concat([widget])
  }
  function unregisterDock(widget) {
    dockWidgets = dockWidgets.filter(function(w) { return w !== widget })
  }
  function dockWidgetFor(screenName) {
    for (var i = 0; i < dockWidgets.length; i++)
      if (dockWidgets[i].screenName === screenName) return dockWidgets[i]
    return dockWidgets.length > 0 ? dockWidgets[0] : null
  }

  // Peek preview.
  property var peekPip: null
  property var peekRect: null
  property string peekScreen: ""
  property bool peekHovered: false

  signal flyRequest(string id, var rect, string mode)

  readonly property var floating: pips.filter(function(p) { return !p.docked })
  readonly property var docked: pips.filter(function(p) { return p.docked })

  function pipById(id) { return Model.findPip(pips, id) }

  function fallbackScreen() {
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
  }

  function screenExists(name) {
    for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === name) return true
    return false
  }

  function pipsOnScreen(name) {
    var fallback = fallbackScreen()
    return pips.filter(function(p) {
      var s = p.screen && root.screenExists(p.screen) ? p.screen : fallback
      return s === name
    })
  }

  function setPips(next, persist) {
    pips = next
    if (persist !== false) saveTimer.restart()
  }

  function updatePip(id, patch) {
    setPips(Model.updatePip(pips, id, patch))
  }

  function removePip(id) {
    if (peekPip && peekPip.id === id) endPeek(true)
    setPips(Model.removePip(pips, id))
  }

  function closePip(id) {
    var view = viewFor(id)
    if (view && view.visible) view.close()
    else removePip(id)
  }

  function closeAll() {
    var ids = pips.map(function(p) { return p.id })
    for (var i = 0; i < ids.length; i++) closePip(ids[i])
  }

  function toggleSticky(id, workspaceId) {
    var p = pipById(id)
    if (!p) return
    updatePip(id, p.sticky ? { sticky: false, workspace: workspaceId || p.workspace } : { sticky: true })
  }

  function setSetting(key, value) {
    var next = {}
    for (var k in settings) next[k] = settings[k]
    next[key] = value
    settings = Model.normalizeSettings(next)
    saveSettingsTimer.restart()
  }

  function cycleSetting(key) {
    settings = Model.cycleSetting(settings, key)
    saveSettingsTimer.restart()
  }

  function resetSettings() {
    settings = Model.normalizeSettings({})
    saveSettingsTimer.restart()
  }

  // ---------------------------------------------------------- windows
  // address (no 0x) -> HyprlandToplevel
  readonly property var toplevelMap: {
    var out = {}
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var a = Model.cleanAddress(list[i].address)
      if (a) out[a] = list[i]
    }
    return out
  }

  function captureSourceFor(p) {
    if (!p) return null
    if (p.kind === "window") {
      var t = toplevelMap[p.address]
      return t && t.wayland ? t.wayland : null
    }
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === p.monitor) return Quickshell.screens[i]
    return null
  }

  function ipcOf(t) {
    var o = t ? t.lastIpcObject : null
    return o && typeof o === "object" ? o : null
  }

  function activeWorkspaceIds() {
    var out = []
    var list = Hyprland.monitors.values
    for (var i = 0; i < list.length; i++)
      if (list[i].activeWorkspace) out.push(list[i].activeWorkspace.id)
    return out
  }

  property int windowRevision: 0
  // Whether a PiP's source window is on a workspace shown right now.
  function sourceVisible(p) {
    var rev = windowRevision
    if (!p || p.kind !== "window") return false
    var o = ipcOf(toplevelMap[p.address])
    if (!o || !o.workspace) return false
    return activeWorkspaceIds().indexOf(o.workspace.id) >= 0
  }

  // Windows on a monitor's active workspace, topmost first, as global
  // logical rectangles.
  function windowsOnMonitor(monitorName) {
    var monitor = null
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].name === monitorName) monitor = mons[i]
    if (!monitor || !monitor.activeWorkspace) return []
    var ws = monitor.activeWorkspace.id
    var out = []
    var list = Hyprland.toplevels.values
    for (var j = 0; j < list.length; j++) {
      var o = ipcOf(list[j])
      if (!o || !o.workspace || o.workspace.id !== ws || o.hidden === true || !o.at || !o.size) continue
      var a = Model.cleanAddress(list[j].address)
      if (!a) continue
      out.push({
        address: a,
        appId: Model.cleanText(o.class, 80),
        title: Model.cleanText(o.title, 120),
        x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1],
        floating: o.floating === true,
        order: typeof o.focusHistoryID === "number" ? o.focusHistoryID : 99,
        fullscreen: !!o.fullscreen
      })
    }
    out.sort(function(a, b) {
      if (a.fullscreen !== b.fullscreen) return a.fullscreen ? -1 : 1
      if (a.floating !== b.floating) return a.floating ? -1 : 1
      return a.order - b.order
    })
    return out
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2"
          || n === "workspace" || n === "workspacev2" || n === "changefloatingmode" || n === "fullscreen"
          || n === "windowtitle" || n === "windowtitlev2" || n === "focusedmon" || n === "activewindowv2")
        refreshWindows.restart()
    }
  }

  Timer {
    id: refreshWindows
    interval: 80
    onTriggered: { Hyprland.refreshToplevels(); root.windowRevision++ }
  }

  function focusSource(id) {
    var p = pipById(id)
    if (!p || p.kind !== "window" || !toplevelMap[p.address]) return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + p.address + '" })')
  }

  // ---------------------------------------------------------- picking
  function pick() {
    if (pips.length >= Model.MAX_PIPS) {
      notify(strings.t("notify.limit").arg(Model.MAX_PIPS))
      return
    }
    endPeek(true)
    Hyprland.refreshToplevels()
    Hyprland.refreshMonitors()
    root.windowRevision++
    selector.open()
  }

  function notify(text) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "OmaPiP", "-g", Model.GLYPHS.pip, "OmaPiP", String(text)])
  }

  function monitorRect(name) {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) {
      if (mons[i].name !== name) continue
      var s = null
      for (var j = 0; j < Quickshell.screens.length; j++) if (Quickshell.screens[j].name === name) s = Quickshell.screens[j]
      return { x: mons[i].x, y: mons[i].y, w: s ? s.width : mons[i].width / mons[i].scale, h: s ? s.height : mons[i].height / mons[i].scale }
    }
    return null
  }

  function edgeInset(edge) {
    var bar = shell && shell.shellConfig && shell.shellConfig.bar ? shell.shellConfig.bar : {}
    var pos = String(bar.position || "top")
    if (pos !== edge) return 0
    return (pos === "top" || pos === "bottom") ? Style.bar.sizeHorizontal : Style.bar.sizeVertical
  }

  // A pick from the selector: { kind, address|monitor, rect, windowRect|monitorRect, screen, localRect }
  function createFromPick(p) {
    if (!p || pips.length >= Model.MAX_PIPS) return
    var areaRect = p.kind === "window" ? p.windowRect : p.monitorRect
    var crop = Model.cropFromRect(p.rect, areaRect)
    var aspect = Model.cropAspect(crop, areaRect.w, areaRect.h)
    var screen = monitorRect(p.screen) || { x: 0, y: 0, w: 1920, h: 1080 }
    var width = Model.startWidth(settings.size, screen.w)
    var height = width / aspect
    // Tall, narrow picks would fill the screen at the usual width.
    if (height > screen.h * 0.5) { height = screen.h * 0.5; width = height * aspect }
    var margin = Style.gapsOut * 2 + 4
    // Corners already taken get the next PiP stacked beside them.
    var pos = Model.cornerPosition(settings.corner, screen.w, screen.h, width, height, margin, edgeInset("top"))
    var stack = pips.filter(function(q) { return !q.docked && q.screen === p.screen }).length
    if (stack > 0) {
      var up = settings.corner === "bl" || settings.corner === "br"
      pos.y = Math.round(pos.y + (up ? -1 : 1) * stack * (height * 0.25 + margin))
    }
    var c = Model.clampPosition(pos.x, pos.y, width, height, screen.w, screen.h)
    var ws = 0
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].name === p.screen && mons[i].activeWorkspace) ws = mons[i].activeWorkspace.id

    idCounter++
    var pip = Model.normalizePip({
      id: Model.newId(Date.now(), idCounter),
      kind: p.kind,
      address: p.address,
      monitor: p.monitor,
      appId: p.appId,
      title: p.title,
      crop: crop,
      screen: p.screen,
      x: c.x, y: c.y,
      width: Math.round(width),
      aspect: aspect,
      opacity: 1,
      sticky: settings.visibility === "all",
      workspace: ws,
      createdAt: Date.now()
    })
    if (!pip) return
    var spawn = {}
    for (var k in spawnRects) spawn[k] = spawnRects[k]
    spawn[pip.id] = { screen: p.screen, x: p.localRect.x, y: p.localRect.y, w: p.localRect.w, h: p.localRect.h }
    spawnRects = spawn
    setPips(pips.concat([pip]))
  }

  function takeSpawnRect(id, screenName) {
    var r = spawnRects[id]
    if (!r) return null
    var next = {}
    for (var k in spawnRects) if (k !== id) next[k] = spawnRects[k]
    spawnRects = next
    return r.screen === screenName ? r : null
  }

  // Window titles change; keep the label current.
  function syncTitles() {
    var changed = false
    var next = pips.map(function(p) {
      if (p.kind !== "window") return p
      var o = root.ipcOf(root.toplevelMap[p.address])
      var title = o ? Model.cleanText(o.title, 120) : p.title
      if (title === p.title || !title) return p
      changed = true
      var q = {}
      for (var k in p) q[k] = p[k]
      q.title = title
      return q
    })
    if (changed) setPips(next, false)
  }
  onWindowRevisionChanged: syncTitles()

  function noteSourceSize(id, w, h) {
    var p = pipById(id)
    if (!p || w <= 0 || h <= 0) return
    var a = Model.cropAspect(p.crop, w, h)
    if (Math.abs(a - p.aspect) / p.aspect > 0.01) updatePip(id, { aspect: a })
  }

  // ------------------------------------------------------- layers/views
  function layerFor(screenName) {
    for (var i = 0; i < layers.instances.length; i++)
      if (layers.instances[i].screenName === screenName) return layers.instances[i]
    return null
  }

  function viewFor(id) {
    var p = pipById(id)
    if (!p) return null
    for (var i = 0; i < layers.instances.length; i++) {
      var v = layers.instances[i].viewFor(id, 0)
      if (v) return v
    }
    return null
  }

  function toLocal(rect, layer) {
    if (!rect || !layer || !layer.monitor) return null
    return { x: rect.x - layer.monitor.x, y: rect.y - layer.monitor.y, w: rect.w, h: rect.h }
  }

  // ------------------------------------------------------------- dock
  function dock(id) {
    var p = pipById(id)
    if (!p || p.docked) return
    var view = viewFor(id)
    var layer = view ? view.host : null
    var widget = layer ? dockWidgetFor(layer.screenName) : null
    var anchor = widget ? widget.iconRect() : null
    var target = anchor && anchor.screen === layer.screenName ? toLocal(anchor, layer) : null
    if (view && view.visible && target && settings.thumbs) {
      view.flyTo({ x: target.x, y: target.y, w: target.h * p.aspect }, function() { root.updatePip(id, { docked: true }) })
    } else {
      updatePip(id, { docked: true })
    }
  }

  function undock(id) {
    var p = pipById(id)
    if (!p || !p.docked) return
    endPeek(true)
    var widget = dockWidgetFor(p.screen)
    var rect = widget ? (widget.thumbRect(id) || widget.iconRect()) : null
    var screen = rect && rect.screen ? rect.screen : p.screen
    // Bring it to the workspace in front of you if it lives on another one.
    var patch = { docked: false }
    if (!p.sticky) {
      var mons = Hyprland.monitors.values
      for (var i = 0; i < mons.length; i++)
        if (mons[i].name === (p.screen || screen) && mons[i].activeWorkspace) patch.workspace = mons[i].activeWorkspace.id
    }
    if (rect) {
      var next = {}
      for (var k in spawnRects) next[k] = spawnRects[k]
      var layer = layerFor(p.screen && screenExists(p.screen) ? p.screen : fallbackScreen())
      var local = toLocal(rect, layer)
      if (local) next[id] = { screen: layer.screenName, x: local.x, y: local.y, w: local.w, h: local.h }
      spawnRects = next
    }
    updatePip(id, patch)
    flyRequest(id, null, "in")
  }

  // Middle click on the bar icon: everything into the bar, or everything out.
  function toggleAll() {
    if (floating.length > 0) {
      var ids = floating.map(function(p) { return p.id })
      for (var i = 0; i < ids.length; i++) dock(ids[i])
    } else {
      var d = docked.map(function(p) { return p.id })
      for (var j = 0; j < d.length; j++) undock(d[j])
    }
  }

  // ------------------------------------------------------------- peek
  function startPeek(id, rect) {
    if (!settings.peek) return
    var p = pipById(id)
    if (!p || !rect) return
    peekClose.stop()
    peekPip = p
    peekRect = rect
    peekScreen = rect.screen || fallbackScreen()
  }
  function endPeek(now) {
    if (now) { peekClose.stop(); peekPip = null; peekRect = null; peekScreen = ""; return }
    peekClose.restart()
  }
  function peekHover(inside) {
    peekHovered = inside
    if (inside) peekClose.stop()
    else peekClose.restart()
  }
  Timer {
    id: peekClose
    interval: 240
    onTriggered: if (!root.peekHovered) { root.peekPip = null; root.peekRect = null; root.peekScreen = "" }
  }
  onPipsChanged: if (peekPip) peekPip = pipById(peekPip.id)

  // ------------------------------------------------------- persistence
  Timer { id: saveTimer; interval: 400; onTriggered: root.saveState() }
  Timer { id: saveSettingsTimer; interval: 300; onTriggered: settingsFile.setText(JSON.stringify(root.settings, null, 2) + "\n") }

  function saveState() {
    if (!stateLoaded) return
    stateFile.setText(JSON.stringify({ version: Model.VERSION, pips: pips }, null, 2) + "\n")
  }

  property string lastSettingsText: ""
  FileView {
    id: settingsFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      root.settings = Model.normalizeSettings(raw)
    }
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  function loadState(text) {
    if (stateLoaded) return
    var raw = null
    try { raw = text ? JSON.parse(text) : null } catch (e) { raw = null }
    var state = Model.normalizeState(raw)
    // Hyprland keeps windows across a shell restart; PiPs of windows that
    // are gone by now are dropped once the window list is known.
    pips = state.pips
    stateLoaded = true
    pruneTimer.restart()
  }

  Timer {
    id: pruneTimer
    interval: 1500
    onTriggered: {
      var keep = root.pips.filter(function(p) { return p.kind !== "window" || !!root.toplevelMap[p.address] })
      if (keep.length !== root.pips.length) root.setPips(keep)
    }
  }

  // --------------------------------------------------------------- UI
  Variants {
    id: layers
    model: Quickshell.screens
    PipLayer {
      service: root
      strings: root.strings
    }
  }

  Selector {
    id: selector
    service: root
    strings: root.strings
  }

  // ---------------------------------------------------------------- IPC
  // omarchy-shell omapip <method>
  ShellIpc {
    target: "omapip"

    function pick(): void { root.pick() }
    function toggle(): void { root.toggleAll() }
    function dockAll(): void { var ids = root.floating.map(function(p) { return p.id }); for (var i = 0; i < ids.length; i++) root.dock(ids[i]) }
    function showAll(): void { var ids = root.docked.map(function(p) { return p.id }); for (var i = 0; i < ids.length; i++) root.undock(ids[i]) }
    function closeAll(): void { root.closeAll() }
    function list(): string {
      return JSON.stringify(root.pips.map(function(p) {
        return { id: p.id, kind: p.kind, label: Model.pipLabel(p), docked: p.docked, sticky: p.sticky, workspace: p.workspace }
      }))
    }
    function settings(): string { return JSON.stringify(root.settings) }
    // Diagnostics: where the bar icons are and what the peek shows.
    function debug(): string {
      return JSON.stringify({
        bars: root.dockWidgets.map(function(w) { return w.iconRect() }),
        peek: { screen: root.peekScreen, pip: root.peekPip ? root.peekPip.id : "", rect: root.peekRect },
        layers: layers.instances.map(function(l) { return { screen: l.screenName, workspace: l.workspaceId, pips: l.pips.length, peeking: l.peeking, visible: l.visible } })
      })
    }
    function set(key: string, value: string): string {
      if (!(key in Model.DEFAULTS)) return "unknown"
      var v = value
      if (value === "true") v = true
      else if (value === "false") v = false
      else if (value !== "" && isFinite(Number(value)) && Model.CHOICES[key] === undefined) v = Number(value)
      root.setSetting(key, v)
      return "ok"
    }
  }
}
