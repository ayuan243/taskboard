const { contextBridge, ipcRenderer } = require('electron')

// Expose a webkit.messageHandlers.app shim so the HTML works unchanged
contextBridge.exposeInMainWorld('webkit', {
  messageHandlers: {
    app: {
      postMessage: (msg) => ipcRenderer.send('app-msg', msg)
    }
  }
})
