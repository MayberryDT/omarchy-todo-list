import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.zet.todo-list"
  ipcTarget: "io.zet.todo-list"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var items: []
  property var history: []
  property bool loaded: false
  property string filter: "open"
  property string searchQuery: ""
  property string lastAddedId: ""
  property string lastPersisted: ""
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color mutedColor: Qt.darker(foreground, 1.6)
  readonly property string storeDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/todo-list"
  readonly property string storePath: storeDir + "/items.json"
  readonly property int historyCap: 100
  readonly property int openCount: items.length
  readonly property var visibleItems: computeVisible(filter, items, history, searchQuery)
  readonly property string emptyText: emptyCopy(filter, items, history, searchQuery)
  readonly property string soundDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/io.zet.todo-list/sounds"
  readonly property string completeSoundPath: soundDir + "/complete.wav"
  readonly property string addSoundPath: soundDir + "/add.wav"
  readonly property string deleteSoundPath: soundDir + "/delete.wav"

  onFilterChanged: {
    searchQuery = ""
    if (addField) addField.text = ""
    syncVisible()
  }

  onSearchQueryChanged: syncVisible()

  function rowDict(item) {
    return {
      id: item.id,
      text: item.text,
      done: item.done,
      createdAt: item.createdAt,
      completedAt: item.completedAt,
      reason: item.reason
    }
  }

  function syncVisible() {
    var rows = computeVisible(filter, items, history, searchQuery)
    var i, k, found, id
    for (i = visibleModel.count - 1; i >= 0; i--) {
      id = String(visibleModel.get(i).id)
      found = false
      for (k = 0; k < rows.length; k++) {
        if (rows[k].id === id) { found = true; break }
      }
      if (!found) visibleModel.remove(i)
    }
    for (i = 0; i < rows.length; i++) {
      found = -1
      for (k = 0; k < visibleModel.count; k++) {
        if (String(visibleModel.get(k).id) === rows[i].id) { found = k; break }
      }
      if (found < 0) visibleModel.insert(i, rowDict(rows[i]))
      else if (found !== i) visibleModel.move(found, i, 1)
    }
    clampSelection()
  }

  function playSound(kind) {
    var proc = sfxComplete
    if (kind === "add") proc = sfxAdd
    else if (kind === "delete") proc = sfxDelete
    proc.running = false
    Qt.callLater(function() { proc.running = true })
  }

  function newId() {
    return Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
  }

  function normalizeItem(item, fallbackDone) {
    if (!item || typeof item.text !== "string") return null
    var text = String(item.text).trim()
    if (!text) return null
    var createdAt = Number(item.createdAt)
    var completedAt = Number(item.completedAt)
    var reason = item.reason === "dismissed" ? "dismissed" : "completed"
    return {
      id: String(item.id || newId()),
      text: text,
      done: item.done === true || fallbackDone === true,
      createdAt: isFinite(createdAt) && createdAt > 0 ? createdAt : Date.now(),
      completedAt: isFinite(completedAt) && completedAt > 0 ? completedAt : 0,
      reason: reason
    }
  }

  function capHistory(list) {
    if (list.length <= historyCap) return list
    return list.slice(0, historyCap)
  }

  function computeVisible(mode, live, archived, query) {
    var out = []
    if (mode === "done") {
      var q = String(query || "").trim().toLowerCase()
      for (var h = 0; h < archived.length; h++) {
        if (!q || String(archived[h].text).toLowerCase().indexOf(q) >= 0) out.push(archived[h])
      }
      return out
    }
    for (var i = 0; i < live.length; i++) out.push(live[i])
    return out
  }

  function applyText(raw) {
    var incoming = String(raw || "")
    if (lastPersisted !== "" && incoming === lastPersisted) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var source = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.items) ? parsed.items : [])
      var histSource = parsed && Array.isArray(parsed.history) ? parsed.history : []
      var next = []
      var nextHist = []
      for (var i = 0; i < source.length; i++) {
        var item = normalizeItem(source[i], false)
        if (!item) continue
        if (item.done) nextHist.push(item)
        else next.push(item)
      }
      for (var h = 0; h < histSource.length; h++) {
        var archived = normalizeItem(histSource[h], true)
        if (archived) nextHist.push(archived)
      }
      items = next
      history = capHistory(nextHist)
    } catch (error) {
      items = []
      history = []
    }
    loaded = true
    lastPersisted = JSON.stringify(snapshot(), null, 2) + "\n"
    syncVisible()
  }

  function snapshot() {
    return {
      version: 1,
      items: items,
      history: history
    }
  }

  function persist() {
    if (!loaded) return
    var text = JSON.stringify(snapshot(), null, 2) + "\n"
    lastPersisted = text
    storeFile.setText(text)
  }

  function addItem(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return false
    var id = newId()
    lastAddedId = id
    var next = items.slice()
    next.unshift({
      id: id,
      text: trimmed,
      done: false,
      createdAt: Date.now(),
      completedAt: 0,
      reason: "completed"
    })
    items = next
    persist()
    syncVisible()
    return true
  }

  function completeItem(id) {
    var next = []
    var archived = history.slice()
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (item.id !== id) {
        next.push(item)
        continue
      }
      archived.unshift(archiveEntry(item, "completed"))
    }
    items = next
    history = capHistory(archived)
    persist()
    syncVisible()
  }

  function archiveEntry(item, reason) {
    return {
      id: item.id,
      text: item.text,
      done: true,
      createdAt: item.createdAt || Date.now(),
      completedAt: item.completedAt || Date.now(),
      reason: reason
    }
  }

  function removeItem(id) {
    if (filter === "done") {
      var kept = []
      for (var h = 0; h < history.length; h++) {
        if (history[h].id !== id) kept.push(history[h])
      }
      history = kept
      persist()
      syncVisible()
      return
    }

    var next = []
    for (var i = 0; i < items.length; i++) {
      if (items[i].id !== id) next.push(items[i])
    }
    items = next
    persist()
    syncVisible()
  }

  function restoreHistory(id) {
    var kept = []
    var found = null
    for (var i = 0; i < history.length; i++) {
      if (history[i].id === id) found = history[i]
      else kept.push(history[i])
    }
    if (!found) return
    history = kept
    var next = items.slice()
    next.unshift({
      id: found.id,
      text: found.text,
      done: false,
      createdAt: found.createdAt || Date.now(),
      completedAt: 0,
      reason: "completed"
    })
    items = next
    persist()
    syncVisible()
  }

  function historyLabel(item) {
    var ms = Number(item.completedAt || item.createdAt || 0)
    if (!ms) return "done"
    return Qt.formatDateTime(new Date(ms), "MMM d")
  }

  function emptyCopy(mode, live, archived, query) {
    if (mode === "done") {
      if (String(query || "").trim() !== "" && archived.length > 0) return "No matches."
      return archived.length === 0 ? "No completed to-dos." : ""
    }
    return live.length === 0 ? "Nothing yet. Type above and press Enter." : ""
  }

  function open() {
    root.controller.show()
    Qt.callLater(function() { root.focusField() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function focusField() {
    cursorActive = false
    selectedIndex = -1
    if (addField) addField.forceActiveFocus()
  }

  function focusList(index) {
    if (visibleModel.count === 0) {
      focusField()
      return
    }
    var next = Math.max(0, Math.min(index, visibleModel.count - 1))
    cursorActive = true
    selectedIndex = next
    if (keyCatcher) keyCatcher.forceActiveFocus()
    ensureSelectedVisible()
  }

  function selectIndex(index) {
    if (index < 0 || index >= visibleModel.count) return
    cursorActive = true
    selectedIndex = index
    ensureSelectedVisible()
  }

  function clampSelection() {
    if (visibleModel.count === 0) {
      if (cursorActive) focusField()
      return
    }
    if (!cursorActive) return
    if (selectedIndex < 0) selectedIndex = 0
    if (selectedIndex >= visibleModel.count) selectedIndex = visibleModel.count - 1
    ensureSelectedVisible()
  }

  function ensureSelectedVisible() {
    if (!cursorActive || selectedIndex < 0 || !rowRepeater || !listFlick) return
    var row = rowRepeater.itemAt(selectedIndex)
    if (!row) return
    var y = row.y
    var top = listFlick.contentY
    var bottom = top + listFlick.height
    if (y < top) listFlick.contentY = Math.max(0, y)
    else if (y + row.height > bottom)
      listFlick.contentY = Math.max(0, y + row.height - listFlick.height)
  }

  function moveCursor(dx, dy) {
    if (dx !== 0) {
      root.filter = root.filter === "open" ? "done" : "open"
      return
    }
    if (dy === 0) return
    if (!cursorActive) {
      focusList(dy > 0 ? 0 : visibleModel.count - 1)
      return
    }
    var next = selectedIndex + dy
    if (next < 0) {
      focusField()
      return
    }
    if (next >= visibleModel.count) next = visibleModel.count - 1
    selectedIndex = next
    ensureSelectedVisible()
  }

  function selectedRow() {
    if (!cursorActive || selectedIndex < 0 || !rowRepeater) return null
    return rowRepeater.itemAt(selectedIndex)
  }

  function activateCursor() {
    var row = selectedRow()
    if (row) row.activate()
  }

  function deleteSelected() {
    var row = selectedRow()
    if (row) row.begin("delete")
  }

  Process {
    id: ensureDir
    command: ["bash", "-c", "mkdir -p \"$1\"; f=\"$1/items.json\"; [[ -f \"$f\" ]] || printf '{ \"version\": 1, \"items\": [], \"history\": [] }\\n' > \"$f\"", "todo-list-init", root.storeDir]
    running: true
    onExited: storeFile.reload()
  }

  FileView {
    id: storeFile
    path: root.storePath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.applyText(text())
    onLoadFailed: root.applyText("{}")
    onFileChanged: reload()
  }

  ListModel {
    id: visibleModel
  }

  Process {
    id: sfxComplete
    command: ["pw-play", "--volume=0.28", "--media-role=Notification", root.completeSoundPath]
  }

  Process {
    id: sfxAdd
    command: ["pw-play", "--volume=0.20", "--media-role=Notification", root.addSoundPath]
  }

  Process {
    id: sfxDelete
    command: ["pw-play", "--volume=0.15", "--media-role=Notification", root.deleteSoundPath]
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function dump(): string { return JSON.stringify(root.snapshot()) }
    function add(text: string): string { return root.addItem(text) ? "ok" : "empty" }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: addField
    contentWidth: panel.fittedContentWidth(Style.space(292))
    contentHeight: panel.cappedContentHeight(Style.space(360))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: addField.activeFocus
      onCloseRequested: {
        if (root.cursorActive) root.focusField()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.deleteSelected()
      onTextKey: function(t) {
        if (t === "[") root.filter = "open"
        else if (t === "]") root.filter = "done"
        else if (t === "/") root.focusField()
      }
      Keys.onDeletePressed: function(event) {
        if (keyCatcher.blocked) return
        root.deleteSelected()
        event.accepted = true
      }

      Item {
        anchors.fill: parent

        Column {
          id: chrome
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: Math.max(titleRow.implicitHeight, tabTrack.height)

            Row {
              id: titleRow
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: "TO-DOS"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: root.openCount === 1 ? "1 open" : root.openCount + " open"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Rectangle {
              id: tabTrack
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(22)
              width: openTab.width + doneTab.width + Style.space(4)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

              Rectangle {
                x: Style.space(2) + (root.filter === "open" ? 0 : openTab.width)
                y: Style.space(2)
                width: root.filter === "open" ? openTab.width : doneTab.width
                height: parent.height - Style.space(4)
                radius: Math.max(0, Style.cornerRadius - 1)
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              }

              Row {
                id: tabRow
                anchors.fill: parent
                anchors.margins: Style.space(2)
                spacing: 0

                Item {
                  id: openTab
                  width: openLabel.implicitWidth + Style.space(14)
                  height: parent.height

                  Text {
                    id: openLabel
                    anchors.centerIn: parent
                    text: "Open"
                    color: root.filter === "open" ? root.foreground : root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.filter === "open"
                    Behavior on color { ColorAnimation { duration: 120 } }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.filter = "open"
                  }
                }

                Item {
                  id: doneTab
                  width: doneLabel.implicitWidth + Style.space(14)
                  height: parent.height

                  Text {
                    id: doneLabel
                    anchors.centerIn: parent
                    text: "Done"
                    color: root.filter === "done" ? root.foreground : root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: root.filter === "done"
                    Behavior on color { ColorAnimation { duration: 120 } }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.filter = "done"
                  }
                }
              }
            }
          }

          TextField {
            id: addField
            width: parent.width
            foreground: root.foreground
            placeholderText: root.filter === "done" ? "Search done" : "Add a to-do"
            font.pixelSize: Style.font.bodySmall
            verticalPadding: Style.space(6)
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down) {
                root.focusList(root.cursorActive && root.selectedIndex >= 0 ? root.selectedIndex : 0)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (text !== "") text = ""
                else root.close()
                event.accepted = true
              } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
                event.accepted = true
              }
            }
            onTextChanged: {
              if (root.filter === "done") root.searchQuery = text
            }
            onAccepted: {
              if (root.filter === "done") return
              if (root.addItem(text)) {
                root.playSound("add")
                text = ""
              }
            }
          }
        }

        Flickable {
          id: listFlick
          anchors.top: chrome.bottom
          anchors.topMargin: Style.space(10)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          contentWidth: width
          contentHeight: listBody.implicitHeight
          flickDeceleration: 4000

          Column {
            id: listBody
            width: listFlick.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.emptyText
              color: root.mutedColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              opacity: visibleModel.count === 0 ? 1 : 0
              height: opacity > 0.01 ? implicitHeight : 0
              Behavior on opacity { NumberAnimation { duration: 140 } }
              Behavior on height { NumberAnimation { duration: 140 } }
            }

            Repeater {
              id: rowRepeater
              model: visibleModel

              delegate: TodoRow {
                required property string id
                required property string text
                required property var done
                required property var createdAt
                required property var completedAt
                required property string reason
                required property int index
                width: listBody.width
                panel: root
                item: ({
                  id: id,
                  text: text,
                  done: done,
                  createdAt: createdAt,
                  completedAt: completedAt,
                  reason: reason
                })
                filter: root.filter
                appearIndex: index
                selected: root.cursorActive && root.selectedIndex === index
                foreground: root.foreground
                mutedColor: root.mutedColor
                fontFamily: root.fontFamily
              }
            }
          }
        }
      }
    }
  }
}
