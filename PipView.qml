import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "PipModel.js" as Model

// One floating PiP on one screen: a live, cropped picture of a window or a
// screen region. Drag to move, wheel to resize, Ctrl+wheel for opacity,
// double-click to jump to the source, right-click to dock it in the bar,
// middle-click to close.
Item {
  id: root

  property var pip: null
  property var service: null
  property var host: null         // the PipLayer it lives in
  property var strings: null

  readonly property var settings: service ? service.settings : Model.normalizeSettings({})
  readonly property var motion: service ? service.motion : Model.motion("extreme")
  readonly property string pipId: pip ? pip.id : ""
  readonly property real aspect: pip ? pip.aspect : 16 / 9

  function dur(ms) { return Style.duration(Math.round(ms * motion.speed)) }
  function t(key, fallback) { return strings ? strings.t(key) : fallback }
  readonly property int springType: motion.springy ? Easing.OutBack : Easing.OutCubic
  readonly property real overshoot: motion.flair > 1 ? 1.25 : 0.7

  // ------------------------------------------------------------ geometry
  // gx/gy/gw: where the PiP is now. They ease toward the saved position
  // unless the pointer is moving it.
  property real gx: pip ? pip.x : 0
  property real gy: pip ? pip.y : 0
  property real gw: pip ? pip.width : 320
  readonly property real gh: gw / aspect
  property bool dragging: false
  property bool resizing: false
  property bool instant: false
  property bool flying: false
  property bool closing: false

  readonly property bool easing: !dragging && !resizing && !instant
  Behavior on gx { enabled: root.easing; NumberAnimation { duration: root.dur(260); easing.type: root.springType; easing.overshoot: root.overshoot } }
  Behavior on gy { enabled: root.easing; NumberAnimation { duration: root.dur(260); easing.type: root.springType; easing.overshoot: root.overshoot } }
  Behavior on gw { enabled: root.easing; NumberAnimation { duration: root.dur(240); easing.type: root.springType; easing.overshoot: root.overshoot } }

  function syncFromModel() {
    if (!pip || dragging || resizing || flying) return
    gx = pip.x; gy = pip.y; gw = pip.width
  }
  onPipChanged: syncFromModel()

  // ---------------------------------------------------------- visibility
  readonly property var source: service && pip ? service.captureSourceFor(pip) : null
  readonly property bool sourceGone: !!pip && pip.kind === "window" && !source
  readonly property bool sourceOnScreen: service && pip ? service.sourceVisible(pip) : false
  readonly property bool wanted: !!pip && !closing && !pip.docked
    && Model.visibleOn(pip, host ? host.screenName : "", host ? host.workspaceId : 0)
    && !(settings.hideWhenSourceVisible && sourceOnScreen)

  property real shown: 0
  Behavior on shown { enabled: !root.flying; NumberAnimation { duration: root.dur(root.wanted ? 240 : 150); easing.type: Easing.OutCubic } }
  onWantedChanged: if (!flying) shown = wanted ? 1 : 0
  visible: shown > 0.001 || flying
  readonly property bool interactive: wanted && shown > 0.5 && !flying && !closing

  // ------------------------------------------------------------- hover
  readonly property bool hovered: mouse.containsMouse || dragging || resizing || chromeHover
  property bool chromeHover: false
  readonly property bool growing: settings.hover === "grow" && hovered && !dragging && !resizing
  property real grow: growing ? 1 : 0
  Behavior on grow { NumberAnimation { duration: root.dur(root.growing ? 220 : 160); easing.type: root.growing ? root.springType : Easing.OutCubic; easing.overshoot: root.overshoot * 0.8 } }
  readonly property bool ghosted: settings.hover === "ghost" && mouse.containsMouse && !dragging && !resizing

  // Grow toward the middle of the screen, from the corner nearest an edge.
  readonly property real layerW: host ? host.width : 1920
  readonly property real layerH: host ? host.height : 1080
  readonly property bool anchorRight: gx + gw / 2 > layerW / 2
  readonly property bool anchorBottom: gy + gh / 2 > layerH / 2
  readonly property real factor: 1 + (settings.hoverScale - 1) * grow
  readonly property real cardW: gw * factor
  readonly property real cardH: gh * factor

  // Where it slides from and to when its workspace comes and goes.
  readonly property real slide: (host ? host.workspaceDirection : 1) * Math.min(120, gw * 0.4) * motion.flair

  x: (anchorRight ? gx + gw - cardW : gx) + (1 - shown) * slide
  y: anchorBottom ? gy + gh - cardH : gy
  width: cardW
  height: cardH
  z: hovered ? 10 : (dragging ? 20 : 0)

  readonly property real radius: settings.radius >= 0 ? settings.radius : Math.max(Style.cornerRadius, 8)
  property real borderWidth: settings.border === "none" ? 0 : (hovered ? 3 : 2)
  Behavior on borderWidth { NumberAnimation { duration: root.dur(140) } }

  // The card, scaled and faded as a whole for entrances and exits.
  Item {
    id: card
    anchors.fill: parent
    opacity: root.shown * (root.ghosted ? 0.14 : (root.pip ? root.pip.opacity : 1) * root.settings.opacity)
    scale: 0.94 + 0.06 * root.shown
    Behavior on opacity { enabled: root.shown >= 1; NumberAnimation { duration: root.dur(180); easing.type: Easing.OutCubic } }

    // Shadow, deeper while hovered.
    RectangularShadow {
      anchors.fill: frameItem
      visible: root.settings.shadow
      radius: root.radius + root.borderWidth
      blur: root.hovered ? 36 : 22
      spread: root.hovered ? 2 : 0
      offset.y: root.hovered ? 10 : 6
      color: Qt.rgba(0, 0, 0, root.hovered ? 0.55 : 0.4)
      Behavior on blur { NumberAnimation { duration: root.dur(200) } }
    }

    // Border: a rotating gradient ring, or a flat accent.
    Item {
      id: frameItem
      anchors.fill: parent

      Item {
        id: ringSource
        anchors.fill: parent
        visible: false
        layer.enabled: root.settings.border === "gradient"
        clip: true
        Rectangle {
          id: spinner
          width: Math.hypot(parent.width, parent.height) * 1.2
          height: width
          anchors.centerIn: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Commons.Color.accent }
            GradientStop { position: 0.5; color: Qt.lighter(Commons.Color.accent, 1.6) }
            GradientStop { position: 0.75; color: Commons.Color.foreground }
            GradientStop { position: 1.0; color: Commons.Color.accent }
          }
          RotationAnimation on rotation {
            running: root.visible && root.settings.border === "gradient" && root.motion.flair > 0
            loops: Animation.Infinite
            from: 0; to: 360
            duration: Style.duration(root.hovered ? 2600 : 7000)
          }
        }
      }

      Rectangle {
        id: ringMask
        anchors.fill: parent
        radius: root.radius + root.borderWidth
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        visible: root.settings.border === "gradient" && root.borderWidth > 0
        source: ringSource
        maskEnabled: true
        maskSource: ringMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      Rectangle {
        anchors.fill: parent
        visible: root.settings.border === "accent"
        radius: root.radius + root.borderWidth
        color: Commons.Color.accent
      }

      // The live picture, with rounded corners.
      Item {
        id: contentHolder
        anchors.fill: parent
        anchors.margins: root.borderWidth

        Item {
          id: contentSource
          anchors.fill: parent
          visible: false
          layer.enabled: true

          Rectangle {
            anchors.fill: parent
            visible: root.settings.background === "theme"
            color: Commons.Color.background
          }

          LiveSource {
            id: live
            anchors.fill: parent
            captureSource: root.source
            crop: root.pip ? root.pip.crop : ({ x: 0, y: 0, w: 1, h: 1 })
            refresh: root.pip && root.pip.refresh ? root.pip.refresh : root.settings.refresh
            paintCursor: root.settings.paintCursor
            active: root.visible
            onSourceSizeChanged: if (root.service && root.pip && sourceSize.width > 0)
              root.service.noteSourceSize(root.pip.id, sourceSize.width, sourceSize.height)
          }

          // Waiting for the first frame, or the window is gone.
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.85)
            opacity: !live.hasContent || root.sourceGone ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.dur(220) } }
            Column {
              anchors.centerIn: parent
              spacing: Style.space(4)
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.sourceGone ? Model.GLYPHS.eyeOff : Model.GLYPHS.pip
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Math.min(Style.font.displayLarge, root.height / 3)
                SequentialAnimation on opacity {
                  running: !live.hasContent && !root.sourceGone && root.visible
                  loops: Animation.Infinite
                  NumberAnimation { from: 0.3; to: 1; duration: Style.duration(600) }
                  NumberAnimation { from: 1; to: 0.3; duration: Style.duration(600) }
                }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.sourceGone && root.height > 80
                textFormat: Text.PlainText
                text: root.t("pip.sourceClosed", "Window closed")
                color: Commons.Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Rectangle {
          id: contentMask
          anchors.fill: parent
          radius: root.radius
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: parent
          source: contentSource
          maskEnabled: true
          maskSource: contentMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1.0
        }
      }
    }

    // ---------------------------------------------------------- chrome
    Item {
      id: chrome
      anchors.fill: parent
      anchors.margins: root.borderWidth
      readonly property bool show: root.hovered && !root.dragging && !root.ghosted && root.settings.hover !== "dodge" && root.interactive
      opacity: show ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: root.dur(chrome.show ? 180 : 120) } }
      visible: opacity > 0.01

      // Title strip.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(parent.height * 0.45, Style.space(44))
        topLeftRadius: root.radius
        topRightRadius: root.radius
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.62) }
          GradientStop { position: 1; color: "transparent" }
        }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          width: parent.width - Style.space(10) - buttons.width - Style.space(12)
          y: Style.space(7)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          visible: root.width > 220
          text: Model.pipLabel(root.pip)
          color: "white"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: buttons
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(5)
        spacing: Style.space(3)
        layoutDirection: Qt.RightToLeft

        Repeater {
          // Only the keys: rebuilding on every PiP change would recreate the
          // buttons under the pointer.
          model: ScriptModel {
            values: {
              var keys = ["close", "dock", "sticky", "opacity", "through", "focus"]
              if (root.pip && root.pip.kind !== "window") keys.pop()
              var room = Math.max(1, Math.floor((root.gw - Style.space(10)) / (Style.space(26) + Style.space(3))))
              return keys.slice(0, room)
            }
          }

          Rectangle {
            id: btn
            required property string modelData
            required property int index
            readonly property string glyph: root.glyphFor(modelData)
            readonly property string tip: root.tipFor(modelData)
            onTipChanged: if (btnMouse.containsMouse) chrome.tipText = tip
            width: Style.space(26)
            height: width
            radius: width / 2
            color: btnMouse.containsMouse
              ? (modelData === "close" ? Commons.Color.urgent : Commons.Color.accent)
              : Qt.rgba(0, 0, 0, 0.5)
            Behavior on color { ColorAnimation { duration: root.dur(120) } }
            // Pop in one after another.
            scale: chrome.show ? (btnMouse.pressed ? 0.86 : (btnMouse.containsMouse ? 1.12 : 1)) : 0.5
            Behavior on scale {
              SequentialAnimation {
                PauseAnimation { duration: chrome.show && root.motion.flair > 0 ? root.dur(btn.index * 28) : 0 }
                NumberAnimation { duration: root.dur(180); easing.type: root.springType; easing.overshoot: root.overshoot * 1.6 }
              }
            }
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: btn.glyph
              color: "white"
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
            }
            MouseArea {
              id: btnMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: {
                root.chromeHover = containsMouse
                if (containsMouse) {
                  chrome.tipText = btn.tip
                  chrome.tipCenterX = btn.mapToItem(chrome, btn.width / 2, 0).x
                  tipDelay.restart()
                } else {
                  tipDelay.stop()
                  chrome.tipShown = false
                }
              }
              onClicked: root.action(btn.modelData)
            }
          }
        }
      }

      // Tooltip for the buttons: drops in under the hovered one.
      property string tipText: ""
      property real tipCenterX: 0
      property bool tipShown: false
      Timer { id: tipDelay; interval: 280; onTriggered: chrome.tipShown = true }
      onShowChanged: if (!show) { tipDelay.stop(); tipShown = false }

      Rectangle {
        id: tip
        readonly property bool on: chrome.tipShown && chrome.show
        z: 5
        width: tipLabel.implicitWidth + Style.space(16)
        height: tipLabel.implicitHeight + Style.space(8)
        radius: height / 2
        x: Math.max(Style.space(4), Math.min(chrome.width - width - Style.space(4), chrome.tipCenterX - width / 2))
        y: buttons.y + buttons.height + Style.space(6) + (on ? 0 : -Style.space(6))
        color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.94)
        border.width: 1
        border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.7)
        opacity: on ? 1 : 0
        scale: on ? 1 : 0.9
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: root.dur(on ? 160 : 100) } }
        Behavior on y { NumberAnimation { duration: root.dur(180); easing.type: root.springType; easing.overshoot: root.overshoot } }
        Behavior on scale { NumberAnimation { duration: root.dur(180); easing.type: root.springType; easing.overshoot: root.overshoot } }
        Behavior on x { enabled: tip.on; NumberAnimation { duration: root.dur(140); easing.type: Easing.OutCubic } }
        Text {
          id: tipLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: chrome.tipText
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // Resize grip in the corner facing the middle of the screen.
      Text {
        id: grip
        textFormat: Text.PlainText
        text: Model.GLYPHS.resize
        color: "white"
        style: Text.Outline
        styleColor: Qt.rgba(0, 0, 0, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.iconLarge
        // In the free corner: opposite the edges the PiP is anchored to.
        x: root.anchorRight ? Style.space(4) : parent.width - width - Style.space(4)
        y: root.anchorBottom ? Style.space(36) : parent.height - height - Style.space(4)
        rotation: root.anchorRight ? (root.anchorBottom ? 180 : 90) : (root.anchorBottom ? -90 : 0)
        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.SizeFDiagCursor
          property real startW: 0
          property real startX: 0
          property real startY: 0
          onContainsMouseChanged: root.chromeHover = containsMouse
          onPressed: function(m) {
            var p = mapToItem(null, m.x, m.y)
            startX = p.x; startY = p.y; startW = root.gw
            root.resizing = true
          }
          onPositionChanged: function(m) {
            if (!pressed) return
            var p = mapToItem(null, m.x, m.y)
            var dx = (p.x - startX) * (root.anchorRight ? -1 : 1)
            var dy = (p.y - startY) * (root.anchorBottom ? -1 : 1)
            var d = Math.abs(dx) > Math.abs(dy * root.aspect) ? dx : dy * root.aspect
            var w = Math.max(Model.MIN_WIDTH, Math.min(root.hostW, startW + d))
            // Keep the far corner still.
            if (root.anchorRight) root.gx = root.gx + root.gw - w
            if (root.anchorBottom) root.gy = root.gy + root.gh - w / root.aspect
            root.gw = w
          }
          onReleased: { root.resizing = false; root.commitGeometry() }
        }
      }
    }

    // A ring that ripples out when a PiP lands.
    Rectangle {
      id: ripple
      anchors.centerIn: parent
      width: parent.width; height: parent.height
      radius: root.radius
      color: "transparent"
      border.width: 3
      border.color: Commons.Color.accent
      opacity: 0
    }
    ParallelAnimation {
      id: landRipple
      NumberAnimation { target: ripple; property: "opacity"; from: 0.9; to: 0; duration: root.dur(520); easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.18; duration: root.dur(520); easing.type: Easing.OutCubic }
    }
  }

  // ------------------------------------------------------------- input
  MouseArea {
    id: mouse
    anchors.fill: parent
    z: -1
    enabled: root.interactive
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property real offX: 0
    property real offY: 0
    property real pressGX: 0
    property real pressGY: 0

    onPositionChanged: function(m) {
      if (root.settings.hover === "dodge" && !pressed && !(m.modifiers & Qt.AltModifier)) { root.dodge(); return }
      if (!pressed || !(m.buttons & Qt.LeftButton)) return
      var p = mapToItem(root.host ? root.host.stage : null, m.x, m.y)
      if (!root.dragging && Math.abs(p.x - pressGX) + Math.abs(p.y - pressGY) < 4) return
      root.dragging = true
      root.gx = p.x - offX
      root.gy = p.y - offY
    }
    onPressed: function(m) {
      if (m.button !== Qt.LeftButton) return
      var p = mapToItem(root.host ? root.host.stage : null, m.x, m.y)
      pressGX = p.x; pressGY = p.y
      // Grab where the pointer is on the resting size, not the grown one.
      offX = (p.x - root.x) / root.factor
      offY = (p.y - root.y) / root.factor
    }
    onReleased: function(m) {
      if (m.button === Qt.LeftButton && root.dragging) {
        root.dragging = false
        root.commitGeometry()
      }
    }
    onClicked: function(m) {
      if (m.button === Qt.RightButton) root.action("dock")
      else if (m.button === Qt.MiddleButton) root.action("close")
    }
    onDoubleClicked: function(m) { if (m.button === Qt.LeftButton) root.action("focus") }
    onWheel: function(w) {
      var steps = w.angleDelta.y / 120
      if (w.modifiers & Qt.ControlModifier) {
        var o = Math.max(0.15, Math.min(1, (root.pip ? root.pip.opacity : 1) + steps * 0.05))
        if (root.service) root.service.updatePip(root.pipId, { opacity: o })
        return
      }
      var nw = Math.max(Model.MIN_WIDTH, Math.min(root.hostW, root.gw * (1 + steps * 0.08)))
      if (root.anchorRight) root.gx = root.gx + root.gw - nw
      if (root.anchorBottom) root.gy = root.gy + root.gh - nw / root.aspect
      root.gw = nw
      commitTimer.restart()
    }
  }

  Timer { id: commitTimer; interval: 350; onTriggered: root.commitGeometry() }

  // Save the position after a drag, resize or wheel: snapped, clamped.
  function commitGeometry() {
    if (!service || !pip) return
    var margin = Style.gapsOut * 2 + 4
    var top = host ? host.topInset : 0
    var pos = { x: gx, y: gy }
    if (settings.snap) {
      var s = Model.snapPosition(gx, gy, gw, gh, layerW, layerH, margin, 36, top)
      pos = { x: s.x, y: s.y }
    }
    var c = Model.clampPosition(pos.x, pos.y, gw, gh, layerW, layerH)
    gx = c.x; gy = c.y
    service.updatePip(pipId, { x: c.x, y: c.y, width: Math.round(gw) })
  }

  property bool dodgedRecently: false
  Timer { id: dodgeCooldown; interval: 450; onTriggered: root.dodgedRecently = false }
  function dodge() {
    if (dodgedRecently || !service) return
    dodgedRecently = true
    dodgeCooldown.restart()
    var margin = Style.gapsOut * 2 + 4
    var nx = anchorRight ? margin : layerW - gw - margin
    service.updatePip(pipId, { x: Math.round(nx) })
  }

  function glyphFor(key) {
    var sticky = pip && pip.sticky
    return key === "close" ? Model.GLYPHS.close
      : key === "dock" ? Model.GLYPHS.dock
      : key === "sticky" ? (sticky ? Model.GLYPHS.pin : Model.GLYPHS.pinOff)
      : key === "opacity" ? Model.GLYPHS.opacity
      : key === "through" ? Model.GLYPHS.clickThrough
      : Model.GLYPHS.focus
  }

  function tipFor(key) {
    if (key === "close") return t("pip.close", "Close")
    if (key === "dock") return t("pip.dock", "Dock in the bar")
    if (key === "sticky") return pip && pip.sticky ? t("pip.allWorkspaces", "Every workspace") : t("pip.oneWorkspace", "Only this workspace")
    if (key === "opacity") return t("pip.opacity", "Opacity") + " · " + Math.round((pip ? pip.opacity : 1) * 100) + "%"
    if (key === "through") return t("pip.clickThrough", "Click through")
    return t("pip.focus", "Go to source")
  }

  function action(key) {
    if (!service || !pip) return
    if (key === "close") close()
    else if (key === "dock") service.dock(pipId)
    else if (key === "sticky") service.toggleSticky(pipId, host ? host.workspaceId : 0)
    else if (key === "opacity") {
      var steps = [1, 0.8, 0.6, 0.4]
      var i = 0
      while (i < steps.length && steps[i] > pip.opacity + 0.01) i++
      service.updatePip(pipId, { opacity: steps[(i + 1) % steps.length] })
    }
    else if (key === "through") service.updatePip(pipId, { clickThrough: true })
    else if (key === "focus") service.focusSource(pipId)
  }

  // ------------------------------------------------------- choreography
  // Fly in from a rectangle (the picked region, or a bar thumbnail).
  function flyFrom(rect) {
    flying = true
    instant = true
    gx = rect.x; gy = rect.y; gw = Math.max(24, rect.w)
    shown = 1
    instant = false
    Qt.callLater(function() {
      if (!root.pip) return
      gx = root.pip.x; gy = root.pip.y; gw = root.pip.width
      landTimer.restart()
    })
  }
  Timer {
    id: landTimer
    interval: root.dur(280)
    onTriggered: { root.flying = false; if (root.motion.flair > 0) landRipple.restart() }
  }

  // Fly into a rectangle and then call done().
  property var flyDone: null
  function flyTo(rect, done) {
    flying = true
    flyDone = done
    gx = rect.x; gy = rect.y; gw = Math.max(16, rect.w)
    shrinkFade.restart()
  }
  NumberAnimation {
    id: shrinkFade
    target: root; property: "shown"; from: 1; to: 0
    duration: root.dur(280); easing.type: Easing.InCubic
    onFinished: {
      var cb = root.flyDone
      root.flyDone = null
      root.flying = false
      root.instant = true
      root.syncFromModel()
      root.instant = false
      if (cb) cb()
    }
  }

  // Implode, then remove.
  function close() {
    if (closing) return
    closing = true
    implode.restart()
  }
  ParallelAnimation {
    id: implode
    NumberAnimation { target: card; property: "scale"; to: 0.6; duration: root.dur(200); easing.type: Easing.InBack }
    NumberAnimation { target: card; property: "rotation"; to: root.motion.flair > 1 ? (root.anchorRight ? 6 : -6) : 0; duration: root.dur(200) }
    NumberAnimation { target: root; property: "shown"; to: 0; duration: root.dur(200) }
    onFinished: if (root.service) root.service.removePip(root.pipId)
  }

  // A window that closed takes its PiP with it, after a beat.
  Timer {
    interval: 1400
    running: root.sourceGone && root.settings.closeWhenSourceCloses && !root.closing
    onTriggered: root.close()
  }

  // Undocking: fly out of the bar thumbnail.
  Connections {
    target: root.service
    function onFlyRequest(id, rect, mode) {
      if (id !== root.pipId || mode !== "in") return
      root.closing = false
      var spawn = root.service.takeSpawnRect(id, root.host ? root.host.screenName : "")
      if (spawn) root.flyFrom(spawn)
      else root.shown = root.wanted ? 1 : 0
    }
  }

  Component.onCompleted: {
    var spawn = service && pip ? service.takeSpawnRect(pip.id, host ? host.screenName : "") : null
    if (spawn && wanted) flyFrom(spawn)
    else shown = wanted ? 1 : 0
  }
}
