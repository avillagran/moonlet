import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PipModel.js" as Model

// The picker: click a window, drag a region, or press S for the whole screen.
// A region inside one window follows that window (on any workspace); a region
// across windows mirrors that part of the screen.
Item {
  id: root

  property var service: null
  property var strings: null
  readonly property bool shown: overlay.shown

  // Screen-local logical rectangles of the windows on this workspace,
  // topmost first.
  property var windows: []
  property var hovered: null
  property bool dragging: false
  property real pressX: 0
  property real pressY: 0
  property real dragX: 0
  property real dragY: 0
  property bool confirming: false

  readonly property var motion: service ? service.motion : Model.motion("extreme")
  function dur(ms) { return Style.duration(Math.round(ms * motion.speed)) }
  function t(key, fallback) { return strings ? strings.t(key) : fallback }

  readonly property var dragRect: ({
    x: Math.min(pressX, dragX), y: Math.min(pressY, dragY),
    w: Math.abs(dragX - pressX), h: Math.abs(dragY - pressY)
  })

  // What a release would pick right now.
  readonly property var target: {
    if (dragging) return dragRect
    if (hovered) return { x: hovered.x, y: hovered.y, w: hovered.w, h: hovered.h }
    return { x: 0, y: 0, w: overlay.width, h: overlay.height }
  }

  function open() {
    if (overlay.shown) return
    confirming = false
    dragging = false
    hovered = null
    windows = []
    overlay.shown = true
  }

  function close() {
    overlay.shown = false
    dragging = false
    hovered = null
  }

  function loadWindows() {
    if (!service || !overlay.targetMonitor) { windows = []; return }
    var m = overlay.targetMonitor
    var list = service.windowsOnMonitor(m.name)
    var out = []
    for (var i = 0; i < list.length; i++) {
      var w = list[i]
      out.push({ address: w.address, appId: w.appId, title: w.title,
        x: w.x - m.x, y: w.y - m.y, w: w.w, h: w.h })
    }
    windows = out
  }

  function finish(rect, win) {
    if (!service || !overlay.targetMonitor) { close(); return }
    var m = overlay.targetMonitor
    var global = { x: rect.x + m.x, y: rect.y + m.y, w: rect.w, h: rect.h }
    var pick = win
      ? { kind: "window", address: win.address, appId: win.appId, title: win.title,
          rect: global, windowRect: { x: win.x + m.x, y: win.y + m.y, w: win.w, h: win.h } }
      : { kind: "screen", monitor: m.name,
          rect: global, monitorRect: { x: m.x, y: m.y, w: overlay.width, h: overlay.height } }
    pick.screen = m.name
    pick.localRect = rect
    confirming = true
    flash.restart()
    // Let the confirm flash play, then hand over: the new PiP flies out of the
    // picked rectangle.
    Qt.callLater(function() {
      finishTimer.pick = pick
      finishTimer.restart()
    })
  }

  Timer {
    id: finishTimer
    property var pick: null
    interval: root.dur(140)
    onTriggered: {
      var p = pick
      pick = null
      root.close()
      if (p && root.service) root.service.createFromPick(p)
    }
  }

  OverlayWindow {
    id: overlay
    shownLayer: WlrLayer.Overlay
    shownKeyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "moonlet-picker"

    onContentRevealedChanged: if (contentRevealed) { root.loadWindows(); reload.restart(); keys.forceActiveFocus() }

    // Hyprland answers a window refresh asynchronously: look again shortly.
    Timer {
      id: reload
      interval: 160
      repeat: true
      property int runs: 0
      onRunningChanged: if (running) runs = 0
      onTriggered: {
        root.loadWindows()
        if (pointer.containsMouse && !root.dragging) root.hovered = Model.windowAt(root.windows, pointer.mouseX, pointer.mouseY)
        if (++runs >= 3) stop()
      }
    }

    Item {
      id: stage
      anchors.fill: parent
      LayoutMirroring.enabled: false
      LayoutMirroring.childrenInherit: true

      // The selection, eased toward the target: windows morph into each
      // other, a drag follows the pointer directly.
      Item {
        id: sel
        property real tx: root.target.x
        property real ty: root.target.y
        property real tw: root.target.w
        property real th: root.target.h
        x: tx; y: ty; width: tw; height: th
        Behavior on x { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.6 } }
        Behavior on y { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.6 } }
        Behavior on width { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.6 } }
        Behavior on height { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.6 } }
      }

      // Dim everything but the selection, in four slabs around it.
      readonly property color dim: Qt.rgba(0, 0, 0, root.confirming ? 0.15 : 0.42)
      Rectangle { color: stage.dim; x: 0; y: 0; width: stage.width; height: Math.max(0, sel.y) }
      Rectangle { color: stage.dim; x: 0; y: sel.y + sel.height; width: stage.width; height: Math.max(0, stage.height - sel.y - sel.height) }
      Rectangle { color: stage.dim; x: 0; y: sel.y; width: Math.max(0, sel.x); height: sel.height }
      Rectangle { color: stage.dim; x: sel.x + sel.width; y: sel.y; width: Math.max(0, stage.width - sel.x - sel.width); height: sel.height }

      // The frame: a breathing accent border with corner brackets.
      Item {
        id: frame
        x: sel.x; y: sel.y; width: sel.width; height: sel.height
        opacity: overlay.contentRevealed ? 1 : 0
        scale: overlay.contentRevealed ? 1 : 1.04
        Behavior on opacity { NumberAnimation { duration: root.dur(180); easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: root.dur(220); easing.type: Easing.OutCubic } }

        Rectangle {
          id: glow
          anchors.fill: parent
          anchors.margins: -border.width - 2
          color: "transparent"
          radius: Style.cornerRadius + 4
          border.width: 6
          border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
          SequentialAnimation on opacity {
            running: overlay.shown && root.motion.flair > 0
            loops: Animation.Infinite
            NumberAnimation { from: 0.35; to: 1; duration: Style.duration(900); easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0.35; duration: Style.duration(900); easing.type: Easing.InOutSine }
          }
        }

        Rectangle {
          anchors.fill: parent
          color: root.confirming ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18) : "transparent"
          radius: Style.cornerRadius
          border.width: 2
          border.color: Commons.Color.accent
        }

        Repeater {
          model: 4
          Item {
            required property int index
            readonly property bool isRight: index === 1 || index === 3
            readonly property bool isBottom: index >= 2
            readonly property int len: Math.min(28, frame.width / 3, frame.height / 3)
            x: isRight ? frame.width - len + 3 : -3
            y: isBottom ? frame.height - len + 3 : -3
            width: len; height: len
            scale: root.dragging ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: root.dur(160); easing.type: Easing.OutBack } }
            Rectangle { x: parent.isRight ? parent.width - 4 : 0; width: 4; height: parent.height; color: Commons.Color.foreground; radius: 2 }
            Rectangle { y: parent.isBottom ? parent.height - 4 : 0; width: parent.width; height: 4; color: Commons.Color.foreground; radius: 2 }
          }
        }

        // Confirm flash: the frame pulses out once.
        Rectangle {
          id: flashRing
          anchors.centerIn: parent
          width: parent.width; height: parent.height
          color: "transparent"
          radius: Style.cornerRadius
          border.width: 3
          border.color: Commons.Color.accent
          opacity: 0
        }
        ParallelAnimation {
          id: flash
          NumberAnimation { target: flashRing; property: "opacity"; from: 1; to: 0; duration: root.dur(260); easing.type: Easing.OutCubic }
          NumberAnimation { target: flashRing; property: "scale"; from: 1; to: 1.08; duration: root.dur(260); easing.type: Easing.OutCubic }
        }
      }

      // Size and what it will follow.
      Rectangle {
        id: badge
        readonly property bool isBelow: sel.y + sel.height + height + 12 < stage.height
        x: Math.max(8, Math.min(stage.width - width - 8, sel.x + sel.width / 2 - width / 2))
        y: isBelow ? sel.y + sel.height + 10 : Math.max(8, sel.y - height - 10)
        width: badgeText.implicitWidth + Style.space(20)
        height: badgeText.implicitHeight + Style.space(10)
        radius: height / 2
        color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.6)
        opacity: overlay.contentRevealed && sel.width > 24 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur(150) } }
        Behavior on x { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !root.dragging; NumberAnimation { duration: root.dur(170); easing.type: Easing.OutCubic } }

        Text {
          id: badgeText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          text: {
            var size = Math.round(root.target.w) + " × " + Math.round(root.target.h)
            if (root.dragging) {
              var w = Model.attachRegion(root.dragRect, root.windows)
              return size + "  ·  " + (w ? (w.appId || root.t("picker.window", "Window")) : root.t("picker.screenRegion", "Screen region"))
            }
            if (root.hovered) return size + "  ·  " + Model.cleanText(root.hovered.title || root.hovered.appId, 60)
            return size + "  ·  " + root.t("picker.wholeScreen", "Whole screen")
          }
        }
      }

      // Guides through the pointer, brighter while dragging a region.
      readonly property real px: root.dragging ? root.dragX : pointer.mouseX
      readonly property real py: root.dragging ? root.dragY : pointer.mouseY
      readonly property real guide: !pointer.containsMouse && !root.dragging ? 0 : (root.dragging ? 0.55 : 0.22)
      Rectangle { x: Math.round(stage.px); y: 0; width: 1; height: stage.height; opacity: stage.guide; color: Commons.Color.accent; Behavior on opacity { NumberAnimation { duration: root.dur(140) } } }
      Rectangle { x: 0; y: Math.round(stage.py); width: stage.width; height: 1; opacity: stage.guide; color: Commons.Color.accent; Behavior on opacity { NumberAnimation { duration: root.dur(140) } } }

      // What a click or a drag takes right now, beside the pointer.
      Rectangle {
        id: tag
        readonly property string mode: root.dragging ? "region" : (root.hovered ? "window" : "screen")
        readonly property bool flipX: stage.px + width + 28 > stage.width
        readonly property bool flipY: stage.py + height + 28 > stage.height
        x: flipX ? stage.px - width - 16 : stage.px + 18
        y: flipY ? stage.py - height - 16 : stage.py + 20
        width: tagRow.implicitWidth + Style.space(16)
        height: tagRow.implicitHeight + Style.space(8)
        radius: height / 2
        color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.94)
        border.width: 1
        border.color: Commons.Color.accent
        opacity: pointer.containsMouse && !root.confirming && overlay.contentRevealed ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.dur(140) } }
        Behavior on width { NumberAnimation { duration: root.dur(160); easing.type: Easing.OutCubic } }
        // A pop each time what it takes changes.
        onModeChanged: if (root.motion.flair > 0) tagPop.restart()
        SequentialAnimation {
          id: tagPop
          NumberAnimation { target: tag; property: "scale"; to: 1.18; duration: root.dur(80); easing.type: Easing.OutCubic }
          NumberAnimation { target: tag; property: "scale"; to: 1; duration: root.dur(200); easing.type: Easing.OutBack }
        }
        Row {
          id: tagRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: tag.mode === "region" ? Model.GLYPHS.region : (tag.mode === "window" ? Model.GLYPHS.window : Model.GLYPHS.monitor)
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: tag.mode === "region" ? root.t("picker.tagRegion", "Region")
              : tag.mode === "window" ? root.t("picker.tagWindow", "Window · drag for a region")
              : root.t("picker.tagScreen", "Whole screen · drag for a region")
          }
        }
      }

      // How to use it, dropping in from the top.
      Rectangle {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.contentRevealed ? Style.space(28) : -height
        Behavior on y { NumberAnimation { duration: root.dur(260); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic } }
        width: hintRow.implicitWidth + Style.space(28)
        height: hintRow.implicitHeight + Style.space(14)
        radius: height / 2
        color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)
        opacity: root.dragging ? 0.35 : 1
        Behavior on opacity { NumberAnimation { duration: root.dur(150) } }

        Row {
          id: hintRow
          anchors.centerIn: parent
          spacing: Style.space(14)
          Text {
            textFormat: Text.PlainText
            text: Model.GLYPHS.crosshairs
            color: Commons.Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
            RotationAnimation on rotation {
              running: overlay.shown && root.motion.flair > 1
              loops: Animation.Infinite
              from: -8; to: 8; duration: Style.duration(1400)
              easing.type: Easing.InOutSine
              direction: RotationAnimation.Shortest
            }
          }
          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            text: root.t("picker.hint", "Click a window · drag a region · S whole screen · Esc cancel")
          }
        }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
          else if (event.key === Qt.Key_S) { root.finish({ x: 0, y: 0, w: overlay.width, h: overlay.height }, null); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.finish(root.target, root.dragging ? Model.attachRegion(root.dragRect, root.windows) : root.hovered)
            event.accepted = true
          }
        }
      }

      MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        enabled: !root.confirming
        onPositionChanged: function(mouse) {
          if (pressed && (mouse.buttons & Qt.LeftButton)) {
            if (!root.dragging && (Math.abs(mouse.x - root.pressX) > 6 || Math.abs(mouse.y - root.pressY) > 6)) root.dragging = true
            root.dragX = mouse.x
            root.dragY = mouse.y
          } else {
            root.hovered = Model.windowAt(root.windows, mouse.x, mouse.y)
          }
        }
        onPressed: function(mouse) {
          if (mouse.button === Qt.RightButton) { root.close(); return }
          root.pressX = mouse.x; root.pressY = mouse.y
          root.dragX = mouse.x; root.dragY = mouse.y
        }
        onReleased: function(mouse) {
          if (mouse.button !== Qt.LeftButton) return
          if (root.dragging) {
            var r = root.dragRect
            root.dragging = false
            if (r.w < 24 || r.h < 24) return
            root.finish(r, Model.attachRegion(r, root.windows))
          } else {
            var w = Model.windowAt(root.windows, mouse.x, mouse.y)
            root.finish(w ? { x: w.x, y: w.y, w: w.w, h: w.h } : { x: 0, y: 0, w: overlay.width, h: overlay.height }, w)
          }
        }
      }
    }
  }
}
