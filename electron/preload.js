const { contextBridge, ipcRenderer } = require('electron')

// Expose a webkit.messageHandlers.app shim so the HTML works unchanged
contextBridge.exposeInMainWorld('webkit', {
  messageHandlers: {
    app: {
      postMessage: (msg) => ipcRenderer.send('app-msg', msg)
    }
  }
})

// Let the renderer know it's running inside Electron (not the native Swift shell)
contextBridge.exposeInMainWorld('_isElectron', true)

// Forward main-process callbacks back to the renderer
ipcRenderer.on('cal-error', (_, msg) => {
  if (window.onCalendarError) window.onCalendarError(msg)
})
ipcRenderer.on('cal-events', (_, events) => {
  if (window.applyCalendarEvents) window.applyCalendarEvents(events)
})
ipcRenderer.on('cal-push-done', (_, n) => {
  if (window.onCalendarPushDone) window.onCalendarPushDone(n)
})
ipcRenderer.on('set-pin-state', (_, pinned) => {
  if (window._setPinState) window._setPinState(pinned)
})
