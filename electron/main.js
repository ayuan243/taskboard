const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')

let win
let isPinned = false

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 600,
    minHeight: 360,
    title: '任务板',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    icon: path.join(__dirname, process.platform === 'win32' ? 'icon.ico' : 'icon.icns'),
  })

  win.loadFile(path.join(__dirname, '..', '日历任务板.html'))

  // When window loses focus in pinned mode, send it behind other windows
  win.on('blur', () => {
    if (isPinned) win?.moveTop() === undefined && win?.setAlwaysOnTop(false)
  })
}

app.whenReady().then(() => {
  createWindow()
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })

ipcMain.on('app-msg', (_, msg) => {
  switch (msg.action) {
    case 'quit':
      app.quit()
      break

    case 'hide':
      win?.hide()
      break

    // pin = 固定桌面（沉到普通层，不浮在其他窗口上）
    case 'pin':
      isPinned = true
      win?.setAlwaysOnTop(false)
      win?.webContents.send('set-pin-state', true)
      break

    // unpin = 浮动（始终在最顶层）
    case 'unpin':
      isPinned = false
      win?.setAlwaysOnTop(true, 'floating')
      win?.webContents.send('set-pin-state', false)
      break

    case 'resize':
      if (msg.width && msg.height)
        win?.setSize(Math.round(msg.width), Math.round(msg.height))
      break

    // Calendar sync requires native EventKit (macOS Swift shell only)
    case 'requestCalendarSync':
    case 'pushToCalendar':
      win?.webContents.send('cal-error',
        '日历同步仅 macOS 原生版支持。Windows 版请使用「导出 .ics」文件后手动导入。')
      break
  }
})
