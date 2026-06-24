const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')

let win
let isPinned = false
let _resizeState = null   // tracks active edge-drag in main process

function createWindow() {
  win = new BrowserWindow({
    width: 1280,
    height: 900,
    minWidth: 600,
    minHeight: 360,
    title: '任务板',
    frame: false,           // No title bar / traffic lights (matches Swift .borderless)
    transparent: true,      // True window transparency
    hasShadow: false,
    resizable: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
    icon: path.join(__dirname, process.platform === 'win32' ? 'icon.ico' : 'icon.icns'),
  })

  win.loadFile(path.join(__dirname, '..', '日历任务板.html'))

  // After page loads: restore pin state and ensure transparency works
  win.webContents.on('did-finish-load', () => {
    win.webContents.send('set-pin-state', isPinned)
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

    // pin = 固定桌面（普通层，不浮在其他窗口上）
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

    // Legacy resize (E/S only, kept for safety)
    case 'resize':
      if (msg.width && msg.height)
        win?.setSize(Math.round(msg.width), Math.round(msg.height))
      break

    // ── Edge-drag resize: state lives in main so coords are always correct ──
    case 'startResize':
      if (win) {
        _resizeState = {
          dir:    msg.dir,
          startX: msg.screenX,
          startY: msg.screenY,
          bounds: win.getBounds(),   // logical pixels, authoritative
        }
      }
      break

    case 'doResize':
      if (_resizeState && win) {
        const { dir, startX, startY, bounds } = _resizeState
        const dx = msg.screenX - startX
        const dy = msg.screenY - startY

        let { x, y, width, height } = bounds
        if (dir.includes('e')) width  = Math.max(600, bounds.width  + dx)
        if (dir.includes('s')) height = Math.max(360, bounds.height + dy)
        if (dir.includes('w')) {
          width = Math.max(600, bounds.width - dx)
          x = bounds.x + bounds.width - width
        }
        if (dir.includes('n')) {
          height = Math.max(360, bounds.height - dy)
          y = bounds.y + bounds.height - height
        }
        win.setBounds({ x: Math.round(x), y: Math.round(y), width: Math.round(width), height: Math.round(height) })
      }
      break

    case 'endResize':
      _resizeState = null
      break

    // Calendar sync requires native EventKit — not available in Electron
    case 'requestCalendarSync':
    case 'pushToCalendar':
      win?.webContents.send('cal-error',
        '日历同步仅 macOS 原生版支持。请使用「导出 .ics」文件后在日历 App 中导入。')
      break
  }
})
