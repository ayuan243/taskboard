const { app, BrowserWindow, ipcMain } = require('electron')
const path = require('path')
const { exec } = require('child_process')
const fs = require('fs')
const os = require('os')

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

// ── AppleScript helper (macOS only) ──────────────────────────────────────────
function runAppleScript(script) {
  return new Promise((resolve, reject) => {
    const tmpFile = path.join(os.tmpdir(), `tb_cal_${Date.now()}.scpt`)
    fs.writeFileSync(tmpFile, script, 'utf8')
    exec(`osascript "${tmpFile}"`, { timeout: 30000 }, (err, stdout, stderr) => {
      fs.unlink(tmpFile, () => {})
      if (err) reject(new Error(stderr || err.message))
      else resolve(stdout.trim())
    })
  })
}

// ── Calendar sync error categoriser ─────────────────────────────────────────
function calErrMsg(err) {
  const m = (err.message || '').toLowerCase()
  if (m.includes('not authorized') || m.includes('1743') || m.includes('access')) {
    return '请在「系统设置 → 隐私与安全性 → 日历」中授权任务板，然后重试'
  }
  return '日历操作失败: ' + (err.message || '').slice(0, 120)
}

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

    // ── Calendar sync (macOS: AppleScript; Windows: ICS fallback) ────────────
    case 'requestCalendarSync': {
      if (process.platform !== 'darwin') {
        win?.webContents.send('cal-error', '日历同步仅 macOS 支持，请使用「导出 .ics」文件导入')
        break
      }
      const script = `
set startDate to (current date) - (30 * days)
set endDate to (current date) + (90 * days)
set output to ""
tell application "Calendar"
  set allCals to every calendar
  repeat with c in allCals
    try
      set evts to (every event of c whose start date >= startDate and start date <= endDate)
      repeat with e in evts
        try
          set d to start date of e
          set yr to year of d
          set mo to (month of d) as integer
          set dy to day of d
          set moStr to text -2 thru -1 of ("0" & (mo as string))
          set dyStr to text -2 thru -1 of ("0" & (dy as string))
          set dateStr to (yr as string) & "-" & moStr & "-" & dyStr
          set t to summary of e
          set output to output & dateStr & "|||" & t & "~~~"
        end try
      end repeat
    end try
  end repeat
end tell
return output
`
      runAppleScript(script).then(result => {
        const events = []
        for (const part of result.split('~~~')) {
          const trimmed = part.trim()
          if (!trimmed) continue
          const sep = trimmed.indexOf('|||')
          if (sep < 0) continue
          events.push({ date: trimmed.slice(0, sep).trim(), title: trimmed.slice(sep + 3).trim() })
        }
        win?.webContents.send('cal-events', events)
      }).catch(err => {
        win?.webContents.send('cal-error', calErrMsg(err))
      })
      break
    }

    case 'pushToCalendar': {
      if (process.platform !== 'darwin') {
        win?.webContents.send('cal-error', '日历同步仅 macOS 支持，请使用「导出 .ics」文件导入')
        break
      }
      const events = Array.isArray(msg.events) ? msg.events : []
      if (events.length === 0) { win?.webContents.send('cal-push-done', 0); break }

      const eventBlocks = events.map((evt, i) => {
        const parts = (evt.date || '').split('-').map(Number)
        const [yr, mo, dy] = parts
        if (!yr || !mo || !dy) return ''
        // Escape backslash and double-quote in title for AppleScript string
        const title = (evt.title || '')
          .replace(/\\/g, '\\\\')
          .replace(/"/g, '\\"')
        return `
  set d${i} to current date
  set year of d${i} to ${yr}
  set month of d${i} to ${mo}
  set day of d${i} to ${dy}
  set hours of d${i} to 9
  set minutes of d${i} to 0
  set seconds of d${i} to 0
  if (count of (every event of targetCal whose summary is "${title}" and start date >= d${i} - 60 and start date <= d${i} + 60)) is 0 then
    make new event at end of events of targetCal with properties {summary:"${title}", start date:d${i}, end date:d${i} + 3600, allday event:true}
    set pushCount to pushCount + 1
  end if`
      }).filter(Boolean).join('\n')

      const script = `
tell application "Calendar"
  if not (exists calendar "任务板") then
    make new calendar with properties {name:"任务板"}
  end if
  set targetCal to calendar "任务板"
  set pushCount to 0
${eventBlocks}
  return pushCount
end tell
`
      runAppleScript(script).then(result => {
        win?.webContents.send('cal-push-done', parseInt(result) || 0)
      }).catch(err => {
        win?.webContents.send('cal-error', calErrMsg(err))
      })
      break
    }
  }
})
