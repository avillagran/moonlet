import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "PipModel.js" as Model

// A transparent full-screen surface on one monitor that holds its PiPs. Only
// the PiPs (and an open peek) take input; everything else clicks through.
PanelWindow {
  id: root

  property var service: null
  property var strings: null
  required property var modelData
  screen: modelData

  readonly property string screenName: modelData ? modelData.name : ""
  readonly property var monitor: {
    var list = Hyprland.monitors.values
    for (var i = 0; i < list.length; i++) if (list[i].name === screenName) return list[i]
    return null
  }
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
  property int workspaceDirection: 1
  property int lastWorkspace: 0
  onWorkspaceIdChanged: {
    workspaceDirection = workspaceId >= lastWorkspace ? -1 : 1
    lastWorkspace = workspaceId
  }

  readonly property var settings: service ? service.settings : Model.normalizeSettings({})
  readonly property var motion: service ? service.motion : Model.motion("extreme")
  readonly property real topInset: service ? service.edgeInset("top") : 0
  function dur(ms) { return Style.duration(Math.round(ms * motion.speed)) }

  readonly property var pips: service ? service.pipsOnScreen(screenName) : []
  readonly property bool peeking: !!service && service.peekScreen === screenName && !!service.peekPip

  property alias stage: stage

  // See Service.heartbeat: an invisible pixel that changes, so Hyprland keeps
  // redrawing this monitor and delivering frames of hidden windows.
  property bool beat: false
  Rectangle {
    parent: root.contentItem
    x: 0; y: 0; width: 1; height: 1
    color: Qt.rgba(0, 0, 0, root.beat ? 0.004 : 0.008)
  }
  FrameAnimation {
    running: root.visible && !!root.service && root.service.heartbeat === "live"
    onTriggered: root.beat = !root.beat
  }
  Timer {
    running: root.visible && !!root.service && root.service.heartbeat === "slow"
    interval: 100
    repeat: true
    onTriggered: root.beat = !root.beat
  }

  visible: pips.length > 0 || peeking
  color: "transparent"
  anchors { top: true; left: true; right: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: settings.layer === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "omapip"

  // Input only where a PiP or the peek is.
  mask: Region {
    regions: maskRegions.instances.concat(peekRegion.item ? [peekRegion.item, bridgeRegion.item] : [])
  }

  Variants {
    id: maskRegions
    model: root.pips.filter(function(p) { return !p.clickThrough }).map(function(p) { return p.id })
    Region {
      required property var modelData
      readonly property var view: root.viewFor(modelData, root.viewsRevision)
      readonly property bool on: !!view && view.interactive
      // Bound to the numbers rather than `item`, so the input area follows a
      // PiP as it grows under the pointer.
      x: on ? Math.floor(view.x) : 0
      y: on ? Math.floor(view.y) : 0
      width: on ? Math.ceil(view.width) + 1 : 0
      height: on ? Math.ceil(view.height) + 1 : 0
    }
  }

  // The peek takes the pointer only once it has grown away from the
  // thumbnail: while it grows out of it, it would cover the thumbnail, steal
  // the pointer, then slide away and leave it nowhere, closing itself.
  LazyLoader {
    id: peekRegion
    active: root.peeking && peek.settled
    Region { x: Math.floor(peek.x); y: Math.floor(peek.y); width: Math.ceil(peek.width) + 1; height: Math.ceil(peek.height) + 1 }
  }
  LazyLoader {
    id: bridgeRegion
    active: root.peeking && peek.settled
    Region { x: Math.floor(bridge.x); y: Math.floor(bridge.y); width: Math.ceil(bridge.width); height: Math.ceil(bridge.height) }
  }

  property int viewsRevision: 0
  property var views: ({})
  function viewFor(id, revision) { return views[id] || null }
  function registerView(id, view) {
    var next = {}
    for (var k in views) next[k] = views[k]
    if (view) next[id] = view
    else delete next[id]
    views = next
    viewsRevision++
  }

  Item {
    id: stage
    anchors.fill: parent
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    Repeater {
      model: ScriptModel { values: root.pips.map(function(p) { return p.id }) }
      PipView {
        required property var modelData
        service: root.service
        strings: root.strings
        host: root
        pip: root.service ? root.service.pipById(modelData) : null
        Component.onCompleted: root.registerView(modelData, this)
        Component.onDestruction: root.registerView(modelData, null)
      }
    }

    // ------------------------------------------------------------ peek
    // A large live preview that grows out of a bar thumbnail.
    Item {
      id: peek
      readonly property var pip: root.service ? root.service.peekPip : null
      readonly property var from: root.service ? root.service.peekRect : null
      readonly property real targetW: Math.min(root.width * 0.42, 720)
      readonly property real targetH: pip ? targetW / pip.aspect : 0
      readonly property bool open: root.peeking && !!pip && !!from

      property real amount: open ? 1 : 0
      readonly property bool settled: open && amount > 0.97
      Behavior on amount { NumberAnimation { duration: root.dur(peek.open ? 260 : 150); easing.type: peek.open ? (root.motion.springy ? Easing.OutBack : Easing.OutCubic) : Easing.InCubic; easing.overshoot: 0.9 } }
      visible: amount > 0.01

      readonly property real fx: from ? from.x - (root.monitor ? root.monitor.x : 0) : 0
      readonly property real fy: from ? from.y - (root.monitor ? root.monitor.y : 0) : 0
      readonly property real fw: from ? from.w : 40
      readonly property real fh: from ? from.h : 24
      readonly property bool isBelow: fy < root.height / 2
      readonly property real tx: Math.max(12, Math.min(root.width - targetW - 12, fx + fw / 2 - targetW / 2))
      readonly property real ty: isBelow ? fy + fh + 10 : fy - targetH - 10

      x: fx + (tx - fx) * amount
      y: fy + (ty - fy) * amount
      width: fw + (targetW - fw) * amount
      height: fh + (targetH - fh) * amount

      RectangularShadow {
        anchors.fill: parent
        radius: Style.cornerRadius + 6
        blur: 40
        offset.y: 12
        color: Qt.rgba(0, 0, 0, 0.5 * peek.amount)
      }

      Rectangle {
        anchors.fill: parent
        radius: Math.max(Style.cornerRadius, 8) + 2
        color: Commons.Color.accent
      }

      Item {
        id: peekSource
        anchors.fill: parent
        anchors.margins: 2
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; color: Commons.Color.background }
        LiveSource {
          anchors.fill: parent
          captureSource: peek.pip && root.service ? root.service.captureSourceFor(peek.pip) : null
          crop: peek.pip ? peek.pip.crop : ({ x: 0, y: 0, w: 1, h: 1 })
          refresh: "live"
          paintCursor: root.settings.paintCursor
          active: peek.visible
        }
      }
      Rectangle {
        id: peekMask
        anchors.fill: peekSource
        radius: Math.max(Style.cornerRadius, 8)
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: peekSource
        source: peekSource
        maskEnabled: true
        maskSource: peekMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(8)
        width: peekLabel.implicitWidth + Style.space(18)
        height: peekLabel.implicitHeight + Style.space(8)
        radius: height / 2
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: peek.amount > 0.9 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.dur(140) } }
        Text {
          id: peekLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          color: "white"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: root.strings ? root.strings.t("peek.restore") : "Click to restore"
        }
      }

      MouseArea {
        id: peekMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.service && peek.pip) root.service.undock(peek.pip.id)
      }
    }

    // An invisible strip from the thumbnail to the peek, so moving the
    // pointer down onto the preview never crosses a gap that closes it.
    Item {
      id: bridge
      readonly property real topY: peek.isBelow ? peek.fy + peek.fh - 2 : peek.ty + peek.targetH
      readonly property real bottomY: peek.isBelow ? peek.ty + 2 : peek.fy + 2
      x: peek.fx - 8
      width: peek.fw + 16
      y: topY
      height: Math.max(0, bottomY - topY)
      visible: peek.settled
      MouseArea {
        id: bridgeMouse
        anchors.fill: parent
        hoverEnabled: true
      }
    }

    readonly property bool peekHovered: peekMouse.containsMouse || bridgeMouse.containsMouse
    onPeekHoveredChanged: if (root.service) root.service.peekHover(peekHovered)
  }
}
