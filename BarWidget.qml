import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PipModel.js" as Model

// The bar icon, docked PiPs as live thumbnails beside it (hover one for a
// large preview, click it to bring the PiP back), and a panel that lists every
// PiP and holds the cfg.
Panel {
  id: root
  moduleName: "io.github.avillagran.moonlet"
  ipcTarget: "io.github.avillagran.moonlet"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.avillagran.moonlet") : null
  readonly property var cfg: service ? service.settings : Model.normalizeSettings({})
  readonly property var motion: service ? service.motion : Model.motion("extreme")
  readonly property var pips: service ? service.pips : []
  readonly property var dockedPips: pips.filter(function(p) { return p.docked })
  readonly property bool vertical: !!(bar && bar.vertical)
  readonly property bool showThumbs: cfg.thumbs && !vertical

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  function dur(ms) { return Style.duration(Math.round(ms * motion.speed)) }

  readonly property string screenName: {
    var w = button.QsWindow ? button.QsWindow.window : null
    return w && w.screen ? w.screen.name : ""
  }

  implicitWidth: row.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------- dock geometry
  function globalRect(item) {
    var w = item && item.QsWindow ? item.QsWindow.window : null
    if (!w || !w.screen || !service) return null
    var p = item.mapToItem(w.contentItem, 0, 0)
    var m = service.monitorRect(w.screen.name)
    if (!m) return null
    var pos = bar ? bar.position : "top"
    var ox = pos === "right" ? m.w - w.width : 0
    var oy = pos === "bottom" ? m.h - w.height : 0
    return { screen: w.screen.name, x: m.x + ox + p.x, y: m.y + oy + p.y, w: item.width, h: item.height }
  }
  function iconRect() { return globalRect(button) }
  function thumbRect(id) {
    for (var i = 0; i < thumbRepeater.count; i++) {
      var t = thumbRepeater.itemAt(i)
      if (t && t.pipId === id) return globalRect(t)
    }
    return null
  }

  onServiceChanged: if (service) service.registerDock(root)
  Component.onCompleted: if (service) service.registerDock(root)
  Component.onDestruction: if (service) service.unregisterDock(root)

  function clickAction(kind) {
    var a = kind === "middle" ? cfg.middleClick : (kind === "right" ? cfg.rightClick : cfg.leftClick)
    if (!service) return
    if (a === "pick") { root.close(); service.pick() }
    else if (a === "toggle") service.toggleAll()
    else root.toggle()
  }

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: Style.space(4)
    layoutDirection: bar && bar.position === "right" ? Qt.RightToLeft : Qt.LeftToRight

    BarIconButton {
      id: button
      bar: root.bar
      Layout.fillHeight: true
      Layout.preferredWidth: implicitWidth
      text: Model.GLYPHS.pip
      labelText: !root.showThumbs && root.dockedPips.length > 0 && !root.vertical ? String(root.dockedPips.length) : ""
      slotSize: Style.bar.iconSlot * (labelText !== "" ? 1.6 : 1)
      opacity: root.pips.length > 0 ? 1.0 : 0.65
      onPressed: function(buttonCode) {
        if (buttonCode === Qt.RightButton) root.clickAction("right")
        else if (buttonCode === Qt.MiddleButton) root.clickAction("middle")
        else root.clickAction("left")
      }

      // A pulse when a PiP lands in the bar.
      Rectangle {
        id: pulse
        anchors.centerIn: parent
        width: parent.height * 0.9; height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Commons.Color.accent
        opacity: 0
      }
      ParallelAnimation {
        id: pulseAnim
        NumberAnimation { target: pulse; property: "opacity"; from: 0.9; to: 0; duration: root.dur(420); easing.type: Easing.OutCubic }
        NumberAnimation { target: pulse; property: "scale"; from: 0.6; to: 1.6; duration: root.dur(420); easing.type: Easing.OutCubic }
      }
    }

    Repeater {
      id: thumbRepeater
      model: ScriptModel { values: root.showThumbs ? root.dockedPips.map(function(p) { return p.id }) : [] }

      Item {
        id: thumb
        required property var modelData
        required property int index
        readonly property string pipId: modelData
        readonly property var pip: root.service ? root.service.pipById(pipId) : null
        readonly property real targetH: Math.max(12, (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal) - Style.space(8))
        readonly property real targetW: Math.min(targetH * 3, targetH * (pip ? pip.aspect : 1.6))
        property real appear: 0
        Component.onCompleted: { appear = 1; pulseAnim.restart() }
        Behavior on appear { NumberAnimation { duration: root.dur(320); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 1.6 } }

        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: targetW * Math.min(1, appear)
        Layout.preferredHeight: targetH
        opacity: Math.min(1, appear)

        readonly property bool hot: thumbMouse.containsMouse

        Item {
          id: thumbBody
          anchors.centerIn: parent
          width: thumb.targetW
          height: thumb.targetH
          scale: (0.4 + 0.6 * Math.min(1.2, thumb.appear)) * (thumb.hot ? 1.12 : 1)
          Behavior on scale { NumberAnimation { duration: root.dur(160); easing.type: Easing.OutCubic } }
          y: thumb.hot ? -1 : 0

          Rectangle {
            anchors.fill: parent
            anchors.margins: -1
            radius: Math.max(3, Style.cornerRadius / 2) + 1
            color: thumb.hot ? Commons.Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
            Behavior on color { ColorAnimation { duration: root.dur(120) } }
          }

          Item {
            id: thumbSource
            anchors.fill: parent
            visible: false
            clip: true
            layer.enabled: true
            Rectangle { anchors.fill: parent; color: Commons.Color.background }
            // Cover the thumbnail keeping the crop's shape: a thin strip
            // shows its middle at full height instead of a squashed sliver.
            LiveSource {
              readonly property real shape: thumb.pip ? thumb.pip.aspect : 1.6
              anchors.centerIn: parent
              width: Math.max(parent.width, parent.height * shape)
              height: width / shape
              captureSource: root.service && thumb.pip ? root.service.captureSourceFor(thumb.pip) : null
              crop: thumb.pip ? thumb.pip.crop : ({ x: 0, y: 0, w: 1, h: 1 })
              refresh: root.cfg.refresh
              active: thumb.visible
            }
          }
          Rectangle {
            id: thumbMask
            anchors.fill: parent
            radius: Math.max(3, Style.cornerRadius / 2)
            visible: false
            layer.enabled: true
          }
          MultiEffect {
            anchors.fill: parent
            source: thumbSource
            maskEnabled: true
            maskSource: thumbMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
          }
        }

        MouseArea {
          id: thumbMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: {
            if (!root.service) return
            if (containsMouse) root.service.startPeek(thumb.pipId, root.globalRect(thumb))
            // Leaving for the next thumbnail must not close the peek it opened.
            else if (root.service.peekPip && root.service.peekPip.id === thumb.pipId) root.service.endPeek(false)
          }
          onClicked: function(m) {
            if (!root.service) return
            if (m.button === Qt.MiddleButton) root.service.closePip(thumb.pipId)
            else root.service.undock(thumb.pipId)
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ panel
  property int cursor: 0
  property bool cursorActive: false
  // The cursor moved with the keyboard rather than the mouse: show the
  // hovered setting's help for it too.
  property bool cursorFromKeys: false

  readonly property var settingRows: [
    { key: "visibility", label: strings.t("settings.visibility") },
    { key: "size", label: strings.t("settings.size") },
    { key: "corner", label: strings.t("settings.corner") },
    { key: "hover", label: strings.t("settings.hover") },
    { key: "border", label: strings.t("settings.border") },
    { key: "animation", label: strings.t("settings.animation") },
    { key: "refresh", label: strings.t("settings.refresh") },
    { key: "layer", label: strings.t("settings.layer") },
    { key: "background", label: strings.t("settings.background") },
    { key: "thumbs", label: strings.t("settings.thumbs"), bool: true },
    { key: "peek", label: strings.t("settings.peek"), bool: true },
    { key: "shadow", label: strings.t("settings.shadow"), bool: true },
    { key: "snap", label: strings.t("settings.snap"), bool: true },
    { key: "hideWhenSourceVisible", label: strings.t("settings.hideWhenSourceVisible"), bool: true },
    { key: "closeWhenSourceCloses", label: strings.t("settings.closeWhenSourceCloses"), bool: true },
    { key: "paintCursor", label: strings.t("settings.paintCursor"), bool: true },
    { key: "leftClick", label: strings.t("settings.leftClick") },
    { key: "middleClick", label: strings.t("settings.middleClick") },
    { key: "rightClick", label: strings.t("settings.rightClick") }
  ]
  property bool showSettings: false

  // Every focusable row: actions, PiPs, then settings when open.
  readonly property var rows: {
    var out = [{ type: "action", key: "pick" }]
    if (pips.length > 0) out.push({ type: "action", key: "toggle" }, { type: "action", key: "closeAll" })
    for (var i = 0; i < pips.length; i++) out.push({ type: "pip", id: pips[i].id })
    out.push({ type: "action", key: "settings" })
    if (showSettings) {
      for (var j = 0; j < settingRows.length; j++) out.push({ type: "setting", key: settingRows[j].key })
      out.push({ type: "action", key: "reset" })
    }
    return out
  }
  onRowsChanged: if (cursor >= rows.length) cursor = Math.max(0, rows.length - 1)
  function rowIndex(type, key) {
    for (var i = 0; i < rows.length; i++) if (rows[i].type === type && (rows[i].key === key || rows[i].id === key)) return i
    return -1
  }

  function activate(r) {
    if (!r || !service) return
    if (r.type === "action") {
      if (r.key === "pick") { root.close(); service.pick() }
      else if (r.key === "toggle") service.toggleAll()
      else if (r.key === "closeAll") service.closeAll()
      else if (r.key === "settings") showSettings = !showSettings
      else if (r.key === "reset") service.resetSettings()
    } else if (r.type === "pip") {
      var p = service.pipById(r.id)
      if (!p) return
      if (p.docked) service.undock(r.id)
      else service.dock(r.id)
    } else if (r.type === "setting") {
      var def = Model.DEFAULTS[r.key]
      if (typeof def === "boolean") service.setSetting(r.key, !cfg[r.key])
      else service.cycleSetting(r.key)
    }
  }

  function valueLabel(key) {
    var v = cfg[key]
    if (typeof v === "boolean") return v ? strings.t("value.on") : strings.t("value.off")
    var label = strings.t("value." + key + "." + v)
    return label.indexOf("value.") === 0 ? String(v) : label
  }

  onOpenedChanged: if (opened) { cursorActive = false; cursor = 0 }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.cursorFromKeys = true
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + dy))
      }
      onActivateRequested: {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.activate(root.rows[root.cursor])
      }
      onDeleteRequested: {
        var r = root.rows[root.cursor]
        if (r && r.type === "pip" && root.service) root.service.closePip(r.id)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(6)

          PanelHero {
            width: parent.width
            title: "Moonlet"
            meta: root.pips.length === 0 ? strings.t("panel.empty")
              : strings.tn("panel.count", root.pips.length).arg(Commons.I18n.formatNumber(root.pips.length))
                + (root.dockedPips.length > 0 ? " · " + strings.tn("panel.docked", root.dockedPips.length).arg(Commons.I18n.formatNumber(root.dockedPips.length)) : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.GLYPHS.pip
                color: Commons.Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                SequentialAnimation on rotation {
                  running: root.opened && root.motion.flair > 1
                  loops: 1
                  NumberAnimation { from: -14; to: 0; duration: root.dur(420); easing.type: Easing.OutBack; easing.overshoot: 3 }
                }
              }
            }
          }

          // Actions.
          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.pips.length > 0 ? ["pick", "toggle", "closeAll"] : ["pick"]
              Button {
                required property string modelData
                width: (column.width - Style.space(6) * (root.pips.length > 0 ? 2 : 0)) / (root.pips.length > 0 ? 3 : 1)
                iconText: modelData === "pick" ? Model.GLYPHS.add : (modelData === "toggle" ? (root.service && root.service.floating.length > 0 ? Model.GLYPHS.dock : Model.GLYPHS.undock) : Model.GLYPHS.close)
                text: modelData === "pick" ? strings.t("action.new")
                  : modelData === "toggle" ? (root.service && root.service.floating.length > 0 ? strings.t("action.dockAll") : strings.t("action.showAll"))
                  : strings.t("action.closeAll")
                hasCursor: root.cursorActive && root.rows[root.cursor] && root.rows[root.cursor].key === modelData
                onClicked: root.activate({ type: "action", key: modelData })
              }
            }
          }

          Text {
            visible: root.pips.length === 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: strings.t("panel.help")
          }

          PanelSectionHeader {
            visible: root.pips.length > 0
            width: parent.width
            text: strings.t("panel.pips")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: ScriptModel { values: root.pips.map(function(p) { return p.id }) }
            CursorSurface {
              id: pipRow
              required property var modelData
              required property int index
              readonly property var pip: root.service ? root.service.pipById(modelData) : null
              width: column.width
              implicitHeight: Style.space(56)
              foreground: root.foreground
              hasCursor: root.cursorActive && root.cursor === root.rowIndex("pip", modelData)
              // Slide in, staggered.
              property real enter: 0
              Component.onCompleted: enterAnim.start()
              SequentialAnimation {
                id: enterAnim
                PauseAnimation { duration: root.motion.flair > 0 ? root.dur(pipRow.index * 40) : 0 }
                NumberAnimation { target: pipRow; property: "enter"; to: 1; duration: root.dur(260); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic }
              }
              opacity: enter
              transform: Translate { x: (1 - pipRow.enter) * Style.space(24) }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onEntered: { root.cursorActive = true; root.cursor = root.rowIndex("pip", pipRow.modelData) }
                onClicked: function(m) {
                  if (m.button === Qt.MiddleButton) { if (root.service) root.service.closePip(pipRow.modelData) }
                  else root.activate({ type: "pip", id: pipRow.modelData })
                }
              }

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(10)

                // A live miniature.
                Item {
                  Layout.preferredHeight: Style.space(40)
                  Layout.preferredWidth: Math.min(Style.space(72), Style.space(40) * (pipRow.pip ? pipRow.pip.aspect : 1.6))
                  Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 5; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3) }
                  Rectangle { anchors.fill: parent; radius: 4; color: Commons.Color.background }
                  // Cover the box keeping the crop's shape (see the bar thumbnails).
                  Item {
                    anchors.fill: parent
                    clip: true
                    LiveSource {
                      readonly property real shape: pipRow.pip ? pipRow.pip.aspect : 1.6
                      anchors.centerIn: parent
                      width: Math.max(parent.width, parent.height * shape)
                      height: width / shape
                      captureSource: root.service && pipRow.pip ? root.service.captureSourceFor(pipRow.pip) : null
                      crop: pipRow.pip ? pipRow.pip.crop : ({ x: 0, y: 0, w: 1, h: 1 })
                      refresh: "1"
                      active: root.opened
                    }
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(1)
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: Model.pipLabel(pipRow.pip)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    text: !pipRow.pip ? "" : [
                      pipRow.pip.docked ? strings.t("pip.inBar") : strings.t("pip.floating"),
                      pipRow.pip.sticky ? strings.t("pip.allWorkspaces") : strings.t("pip.workspaceN").arg(pipRow.pip.workspace),
                      Math.round(pipRow.pip.opacity * 100) + "%"
                    ].join(" · ")
                  }
                }

                Repeater {
                  model: [
                    { key: "dock", glyph: pipRow.pip && pipRow.pip.docked ? Model.GLYPHS.undock : Model.GLYPHS.dock },
                    { key: "sticky", glyph: pipRow.pip && pipRow.pip.sticky ? Model.GLYPHS.pin : Model.GLYPHS.pinOff },
                    { key: "through", glyph: pipRow.pip && pipRow.pip.clickThrough ? Model.GLYPHS.clickThrough : Model.GLYPHS.eye },
                    { key: "close", glyph: Model.GLYPHS.close }
                  ]
                  PanelActionButton {
                    required property var modelData
                    iconText: modelData.glyph
                    foreground: root.foreground
                    hoverColor: modelData.key === "close" ? Commons.Color.urgent : Commons.Color.accent
                    fontFamily: root.fontFamily
                    tooltipText: strings.t("tip." + modelData.key)
                    onClicked: {
                      var s = root.service
                      var p = pipRow.pip
                      if (!s || !p) return
                      if (modelData.key === "dock") { if (p.docked) s.undock(p.id); else s.dock(p.id) }
                      else if (modelData.key === "sticky") {
                        var layer = s.layerFor(p.screen || s.fallbackScreen())
                        s.toggleSticky(p.id, layer ? layer.workspaceId : p.workspace)
                      }
                      else if (modelData.key === "through") s.updatePip(p.id, { clickThrough: !p.clickThrough })
                      else if (modelData.key === "close") s.closePip(p.id)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          // Settings, folded away by default.
          CursorSurface {
            width: parent.width
            implicitHeight: Style.space(34)
            foreground: root.foreground
            hasCursor: root.cursorActive && root.cursor === root.rowIndex("action", "settings")
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: { root.cursorActive = true; root.cursor = root.rowIndex("action", "settings") }
              onClicked: root.showSettings = !root.showSettings
            }
            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              Text { textFormat: Text.PlainText; text: Model.GLYPHS.settings; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.icon }
              Text { Layout.fillWidth: true; textFormat: Text.PlainText; text: strings.t("panel.settings"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              Text {
                textFormat: Text.PlainText
                text: Model.GLYPHS.next
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
                rotation: root.showSettings ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: root.dur(200); easing.type: root.motion.springy ? Easing.OutBack : Easing.OutCubic } }
              }
            }
          }

          Column {
            id: settingsColumn
            width: parent.width
            spacing: Style.space(2)
            visible: root.showSettings
            clip: true

            Repeater {
              model: root.showSettings ? root.settingRows : []
              CursorSurface {
                id: settingRow
                required property var modelData
                required property int index
                width: settingsColumn.width
                implicitHeight: Style.space(32)
                foreground: root.foreground
                hasCursor: root.cursorActive && root.cursor === root.rowIndex("setting", modelData.key)
                property real enter: 0
                Component.onCompleted: settingEnter.start()
                SequentialAnimation {
                  id: settingEnter
                  PauseAnimation { duration: root.motion.flair > 0 ? root.dur(settingRow.index * 18) : 0 }
                  NumberAnimation { target: settingRow; property: "enter"; to: 1; duration: root.dur(220); easing.type: Easing.OutCubic }
                }
                opacity: enter
                transform: Translate { y: (1 - settingRow.enter) * -Style.space(8) }

                MouseArea {
                  id: settingMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: { root.cursorActive = true; root.cursorFromKeys = false; root.cursor = root.rowIndex("setting", settingRow.modelData.key) }
                  onClicked: root.activate({ type: "setting", key: settingRow.modelData.key })
                }
                PanelToolTip {
                  visible: settingMouse.containsMouse || (settingRow.hasCursor && root.cursorFromKeys)
                  text: strings.t("help." + settingRow.modelData.key)
                  width: Math.min(implicitWidth, Style.space(300))
                }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: settingRow.modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  ToggleSwitch {
                    visible: !!settingRow.modelData.bool
                    checked: !!root.cfg[settingRow.modelData.key]
                    interactive: false
                    cursorRing: false
                    foreground: root.foreground
                  }
                  Text {
                    id: valueText
                    visible: !settingRow.modelData.bool
                    textFormat: Text.PlainText
                    text: root.valueLabel(settingRow.modelData.key)
                    color: Commons.Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    // A little hop when the value changes.
                    onTextChanged: if (root.motion.flair > 0) hop.restart()
                    SequentialAnimation {
                      id: hop
                      NumberAnimation { target: valueText; property: "scale"; to: 1.25; duration: root.dur(80); easing.type: Easing.OutCubic }
                      NumberAnimation { target: valueText; property: "scale"; to: 1; duration: root.dur(180); easing.type: Easing.OutBack }
                    }
                  }
                }
              }
            }

            // Sliders for the two continuous cfg.
            Repeater {
              model: root.showSettings ? [
                { key: "hoverScale", min: 1.05, max: 2.5, step: 0.05, fmt: function(v) { return "×" + Commons.I18n.formatNumber(v, 2) } },
                { key: "opacity", min: 0.15, max: 1, step: 0.05, fmt: function(v) { return Math.round(v * 100) + "%" } },
                { key: "radius", min: -1, max: 40, step: 1, fmt: function(v) { return v < 0 ? strings.t("value.auto") : Math.round(v) + " px" } }
              ] : []
              Item {
                id: sliderRow
                required property var modelData
                width: settingsColumn.width
                height: Style.space(46)
                HoverHandler { id: sliderHover }
                PanelToolTip {
                  visible: sliderHover.hovered
                  text: strings.t("help." + sliderRow.modelData.key)
                  width: Math.min(implicitWidth, Style.space(300))
                }
                Text {
                  x: Style.space(10)
                  y: Style.space(2)
                  textFormat: Text.PlainText
                  text: strings.t("settings." + modelData.key) + "  " + modelData.fmt(root.cfg[modelData.key])
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                PanelSlider {
                  x: Style.space(10)
                  width: parent.width - Style.space(20)
                  y: Style.space(22)
                  bar: root.bar
                  minimum: modelData.min
                  maximum: modelData.max
                  step: modelData.step
                  value: root.cfg[modelData.key]
                  onReleased: function(v) { if (root.service) root.service.setSetting(modelData.key, v) }
                }
              }
            }

            CursorSurface {
              width: settingsColumn.width
              implicitHeight: Style.space(32)
              foreground: root.foreground
              hasCursor: root.cursorActive && root.cursor === root.rowIndex("action", "reset")
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: { root.cursorActive = true; root.cursor = root.rowIndex("action", "reset") }
                onClicked: if (root.service) root.service.resetSettings()
              }
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: strings.t("settings.reset")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
