import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var panel: null
  property var item: ({})
  property string filter: "open"
  property int appearIndex: 0
  property bool selected: false
  property color foreground: Color.foreground
  property color mutedColor: Qt.darker(foreground, 1.6)
  property string fontFamily: Style.font.family

  property bool doneNow: item && item.done === true
  property bool busy: false
  property string pendingAction: ""
  readonly property bool doneTab: filter === "done"
  readonly property string itemId: item && item.id ? String(item.id) : ""

  readonly property bool editing: panel !== null && panel.editingId === itemId
  readonly property bool dragging: panel !== null && panel.dragId === itemId

  height: Math.max(row.implicitHeight, editing ? editor.implicitHeight : 0) + Style.space(8)
  opacity: 1

  function beginEdit() {
    if (busy || !panel || !itemId) return
    panel.cancelDrag()
    editor.text = String(item.text || "")
    panel.editingId = itemId
    Qt.callLater(function() {
      if (!root.editing) return
      editor.forceActiveFocus()
      editor.selectAll()
    })
  }

  function finishEdit(save) {
    var owner = panel
    var index = appearIndex
    if (!owner) return
    if (save && !owner.editItem(itemId, editor.text)) return
    owner.editingId = ""
    owner.focusList(index)
  }

  function activate() {
    if (root.busy) return
    if (root.doneTab) root.begin("restore")
    else root.begin("complete")
  }

  function begin(action) {
    if (root.busy || !root.itemId) return
    root.busy = true
    root.pendingAction = action
    if (action === "complete") {
      root.doneNow = true
      if (root.panel) root.panel.playSound("complete")
      completeAnim.restart()
      return
    }
    if (action === "uncheck") {
      root.doneNow = false
      leaveAnim.restart()
      return
    }
    if (action === "delete") {
      if (root.panel) root.panel.playSound("delete")
      leaveAnim.restart()
      return
    }
    if (action === "restore") {
      if (root.panel) root.panel.playSound("add")
      leaveAnim.restart()
    }
  }

  function commit() {
    var action = root.pendingAction
    var id = root.itemId
    root.busy = false
    root.pendingAction = ""
    if (!root.panel || !id) return
    if (action === "complete") panel.completeItem(id)
    else if (action === "delete") panel.removeItem(id)
    else if (action === "restore") panel.restoreHistory(id)
  }

  Component.onCompleted: {
    if (root.panel && root.panel.lastAddedId === root.itemId) {
      root.opacity = 0
      slide.y = 8
      appearDelay.start()
    }
  }
  Component.onDestruction: {
    if (!root.busy) return
    root.commit()
  }

  Timer {
    id: appearDelay
    interval: Math.min(root.appearIndex, 5) * 16
    onTriggered: appearAnim.start()
  }

  ParallelAnimation {
    id: appearAnim
    NumberAnimation { target: root; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
    NumberAnimation { target: slide; property: "y"; to: 0; duration: 180; easing.type: Easing.OutCubic }
  }

  SequentialAnimation {
    id: completeAnim
    ParallelAnimation {
      NumberAnimation { target: checkMark; property: "scale"; from: 0.74; to: 1.2; duration: 90; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
      NumberAnimation { target: checkMark; property: "scale"; to: 1.0; duration: 160; easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
    }
    ScriptAction { script: root.commit() }
  }

  SequentialAnimation {
    id: leaveAnim
    ParallelAnimation {
      NumberAnimation { target: root; property: "opacity"; to: 0; duration: 150; easing.type: Easing.InCubic }
      NumberAnimation {
        target: slide
        property: "x"
        to: root.pendingAction === "restore" ? 10 : -10
        duration: 150
        easing.type: Easing.InCubic
      }
    }
    ScriptAction { script: root.commit() }
  }

  transform: Translate { id: slide; x: 0; y: 0 }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Color.accent
    opacity: (hover.containsMouse || root.selected) && !root.busy ? 0.08 : 0
    Behavior on opacity { NumberAnimation { duration: 110 } }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    enabled: !root.busy && !root.editing
    preventStealing: true
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    property real pressY: 0
    property bool moved: false
    onPressed: function(mouse) {
      moved = false
      pressY = mapToItem(root.panel.reorderViewport, mouse.x, mouse.y).y
      root.panel.focusList(root.appearIndex)
    }
    onPositionChanged: function(mouse) {
      if (!pressed || root.doneTab) return
      var point = mapToItem(root.panel.reorderViewport, mouse.x, mouse.y)
      if (!moved && Math.abs(point.y - pressY) < Style.space(8)) return
      moved = true
      root.panel.updateDrag(root.itemId, point.y)
    }
    onReleased: function(mouse) {
      if (moved)
        root.panel.finishDrag(root.itemId, mapToItem(root.panel.reorderViewport, mouse.x, mouse.y))
      else if (containsMouse) root.activate()
      moved = false
    }
    onCanceled: {
      moved = false
      if (root.dragging) root.panel.cancelDrag()
    }
    onContainsMouseChanged: {
      if (containsMouse && root.panel && root.panel.dragId === "" && typeof root.panel.selectIndex === "function")
        root.panel.selectIndex(root.appearIndex)
    }
  }

  Row {
    id: row
    opacity: root.editing ? 0 : root.dragging ? 0.5 : 1
    enabled: !root.editing
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(8)

    Item {
      id: checkMark
      width: checkText.implicitWidth
      height: checkText.implicitHeight
      // Align glyph baselines, not the unequal fallback-font line boxes.
      baselineOffset: checkText.baselineOffset
      anchors.baseline: labelText.baseline
      scale: 1
      transformOrigin: Item.Center

      Text {
        id: checkText
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.doneNow || root.doneTab ? "󰄲" : "󰄱"
        textFormat: Text.PlainText
        color: root.busy && root.pendingAction === "complete"
          ? Color.accent
          : (root.doneNow || root.doneTab ? root.mutedColor : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
      }
    }

    Text {
      id: labelText
      width: Math.max(40, parent.width - parent.spacing * 3 - checkMark.width - (dateText.visible ? dateText.implicitWidth : 0) - deleteText.implicitWidth)
      text: root.item && root.item.text ? root.item.text : ""
      textFormat: Text.PlainText
      color: root.doneNow || root.doneTab ? root.mutedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.strikeout: root.doneNow || root.doneTab
      wrapMode: Text.Wrap
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    Text {
      id: dateText
      visible: root.doneTab
      text: root.panel && root.item ? root.panel.historyLabel(root.item) : ""
      textFormat: Text.PlainText
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.baseline: labelText.baseline
    }

    Text {
      id: deleteText
      text: "󰅖"
      textFormat: Text.PlainText
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      anchors.baseline: labelText.baseline
      opacity: (hover.containsMouse || root.selected) && !root.busy ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }

      MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.begin("delete")
      }
    }
  }

  // A right-button-only overlay leaves checkbox/delete left clicks intact.
  MouseArea {
    anchors.fill: parent
    z: 1
    acceptedButtons: Qt.RightButton
    enabled: !root.busy && !root.editing
    onClicked: root.beginEdit()
  }

  TextField {
    id: editor
    z: 2
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: Style.space(4)
    visible: root.editing
    enabled: visible
    foreground: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    verticalPadding: Style.space(4)
    maximumLength: root.panel ? root.panel.textCap : 500
    onAccepted: root.finishEdit(true)
    Keys.onEscapePressed: function(event) {
      root.finishEdit(false)
      event.accepted = true
    }
    onActiveFocusChanged: {
      // Clicking elsewhere cancels; only Enter commits the edit.
      if (!activeFocus && root.editing) root.panel.editingId = ""
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(2)
    color: Color.accent
    visible: root.panel !== null && root.panel.dragSlot === root.appearIndex
    y: -height / 2
  }
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(2)
    color: Color.accent
    visible: root.panel !== null && root.appearIndex === root.panel.openCount - 1
      && root.panel.dragSlot === root.panel.openCount
    y: parent.height - height / 2
  }

}
