import QtQuick
import Quickshell.Wayland

// A live picture of a window or a screen, cropped to a region, filling this
// item. The crop is in fractions of the source, so it holds when the window
// is resized or moves to another monitor.
Item {
  id: root

  // A Quickshell Toplevel (from HyprlandToplevel.wayland) or a ShellScreen.
  property var captureSource: null
  property var crop: ({ x: 0, y: 0, w: 1, h: 1 })
  // "live", or seconds between frames as a string ("1", "5").
  property string refresh: "live"
  property bool paintCursor: false
  // Stop capturing while nothing shows it.
  property bool active: true

  readonly property bool hasContent: view.hasContent
  readonly property size sourceSize: view.sourceSize
  readonly property bool capturing: active && !!captureSource

  signal sourceStopped()

  clip: true

  ScreencopyView {
    id: view
    readonly property real fullW: root.width / Math.max(0.01, root.crop.w)
    readonly property real fullH: root.height / Math.max(0.01, root.crop.h)
    x: -root.crop.x * fullW
    y: -root.crop.y * fullH
    width: fullW
    height: fullH
    captureSource: root.capturing ? root.captureSource : null
    live: root.capturing && root.refresh === "live"
    paintCursor: root.paintCursor
    onStopped: root.sourceStopped()
  }

  // In live mode Quickshell asks for the next frame only while painting the
  // last one. If a paint is skipped, the chain stops and the picture freezes
  // (a video keeps playing, its PiP doesn't) until something else repaints.
  // Ask again now and then: a no-op while a frame is already on its way.
  Timer {
    running: root.capturing && root.refresh === "live" && view.hasContent
    repeat: true
    interval: 200
    onTriggered: view.captureFrame()
  }

  Timer {
    running: root.capturing && root.refresh !== "live"
    repeat: true
    triggeredOnStart: true
    interval: Math.max(250, Number(root.refresh) * 1000 || 1000)
    onTriggered: view.captureFrame()
  }
}
