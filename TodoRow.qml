import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root
  property var panel: null
  property var item: ({})
  property string filter: "open"
  property int appearIndex: 0
  property color foreground: Color.foreground
  property color mutedColor: Qt.darker(foreground, 1.6)
  property string fontFamily: Style.font.family

  property bool doneNow: item && item.done === true
  property bool busy: false
  property string pendingAction: ""
  readonly property bool doneTab: filter === "done"
  readonly property string itemId: item && item.id ? String(item.id) : ""

  height: row.implicitHeight + Style.space(8)
  opacity: 1

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
    opacity: hover.containsMouse && !root.busy ? 0.08 : 0
    Behavior on opacity { NumberAnimation { duration: 110 } }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(8)

    Item {
      id: checkMark
      width: checkText.implicitWidth
      height: Math.max(checkText.implicitHeight, Style.font.body)
      anchors.verticalCenter: parent.verticalCenter
      scale: 1
      transformOrigin: Item.Center

      Text {
        id: checkText
        anchors.centerIn: parent
        text: root.doneNow || root.doneTab ? "󰄲" : "󰄱"
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
      color: root.doneNow || root.doneTab ? root.mutedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.strikeout: root.doneNow || root.doneTab
      wrapMode: Text.Wrap
      anchors.verticalCenter: parent.verticalCenter
      Behavior on color { ColorAnimation { duration: 140 } }

      MouseArea {
        anchors.fill: parent
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activate()
      }
    }

    Text {
      id: dateText
      visible: root.doneTab
      text: root.panel && root.item ? root.panel.historyLabel(root.item) : ""
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: deleteText
      text: "󰅖"
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
      opacity: hover.containsMouse && !root.busy ? 1 : 0
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
}
