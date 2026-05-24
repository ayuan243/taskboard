const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')

let win

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 600,
    minHeight: 360,
    title: '任务板',
    // macOS: hide title bar but keep traffic lights; Windows: normal frame
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    icon: path.join(__dirname, process.platform === 'win32' ? 'icon.ico' : 'icon.icns'),
  })

  win.loadFile(path.join(__dirname, '..', '日历任务板.html'))
}

app.whenReady().then(() => {
  createWindow()
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })

// Polyfill for window.webkit.messageHandlers.app.postMessage
ipcMain.on('app-msg', (_, msg) => {
  switch (msg.action) {
    case 'quit':   app.quit(); break
    case 'pin':    win?.setAlwaysOnTop(false); break
    case 'unpin':  win?.setAlwaysOnTop(true);  break
    case 'resize':
      if (msg.width && msg.height)
        win?.setSize(Math.round(msg.width), Math.round(msg.height))
      break
  }
})
