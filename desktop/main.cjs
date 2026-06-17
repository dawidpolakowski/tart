const path = require("node:path");
const fs = require("node:fs");
const fsPromises = require("node:fs/promises");
const { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, shell, Tray } = require("electron");
const { formatEntriesAsCsv, formatWeekAsPlainText, TartCoreError, TartStore } = require("./tart-core.cjs");

let mainWindow = null;
let store = null;
let tray = null;
let isQuitting = false;

const exportFormats = {
  csv: {
    extension: "csv",
    label: "CSV",
    mimeType: "text/csv",
  },
  pdf: {
    extension: "pdf",
    label: "PDF",
    mimeType: "application/pdf",
  },
  txt: {
    extension: "txt",
    label: "Plain Text",
    mimeType: "text/plain",
  },
};

function assetPath(fileName) {
  return path.join(__dirname, "..", "assets", fileName);
}

function firstExistingAsset(fileNames) {
  for (const fileName of fileNames) {
    const candidate = assetPath(fileName);

    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  return assetPath("tart-clock-icon.png");
}

function appIconPath() {
  if (process.platform === "darwin") {
    return firstExistingAsset(["tart-clock-icon.icns", "tart-clock-icon.png"]);
  }

  if (process.platform === "win32") {
    return firstExistingAsset(["tart-clock-icon.ico", "tart-clock-icon.png"]);
  }

  return firstExistingAsset(["tart-clock-icon.png"]);
}

function trayIcon() {
  const size = process.platform === "darwin" ? 18 : 16;
  return nativeImage.createFromPath(assetPath("tart-clock-icon.png")).resize({
    height: size,
    width: size,
  });
}

function createStore() {
  store = new TartStore();
}

function showDockIcon() {
  if (process.platform === "darwin" && app.dock) {
    app.dock.show();
  }
}

function hideDockIcon() {
  if (process.platform === "darwin" && app.dock) {
    app.dock.hide();
  }
}

function showMainWindow() {
  showDockIcon();

  if (!mainWindow || mainWindow.isDestroyed()) {
    createWindow();
    return;
  }

  if (mainWindow.isMinimized()) {
    mainWindow.restore();
  }

  mainWindow.setSkipTaskbar(false);
  mainWindow.show();
  mainWindow.focus();
}

function hideMainWindowToTray() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return;
  }

  mainWindow.setSkipTaskbar(true);
  mainWindow.hide();
  hideDockIcon();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1080,
    height: 720,
    minWidth: 900,
    minHeight: 620,
    title: "tart",
    backgroundColor: "#f6f7f3",
    icon: appIconPath(),
    show: false,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(__dirname, "preload.cjs"),
    },
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow.show();
  });

  mainWindow.on("minimize", (event) => {
    event.preventDefault();
    hideMainWindowToTray();
  });

  mainWindow.on("close", (event) => {
    if (isQuitting) {
      return;
    }

    event.preventDefault();
    hideMainWindowToTray();
  });

  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  mainWindow.loadFile(path.join(__dirname, "index.html"));
}

function createTray() {
  if (tray) {
    return;
  }

  tray = new Tray(trayIcon());
  tray.setToolTip("tart");
  tray.setContextMenu(Menu.buildFromTemplate([
    {
      label: "Show tart",
      click: showMainWindow,
    },
    {
      label: "Open log directory",
      click: () => {
        handleDesktopAction(openLogDirectory).then((result) => {
          if (!result.ok) {
            console.error(result.error.message);
          }
        });
      },
    },
    { type: "separator" },
    {
      label: "Quit tart",
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ]));

  tray.on("click", showMainWindow);
  tray.on("double-click", showMainWindow);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function normalizeExportFormat(format) {
  const key = String(format || "").toLowerCase();

  if (!Object.hasOwn(exportFormats, key)) {
    throw new TartCoreError(`unsupported export format: ${format}`);
  }

  return key;
}

function defaultExportPath(week, format) {
  const options = exportFormats[format];
  return path.join(app.getPath("documents"), `tart-${week.weekStart}.${options.extension}`);
}

function buildWeekPdfHtml(week) {
  const entries = week.entries || [];
  const rows = entries.length
    ? entries.map((entry) => `
      <tr>
        <td>${escapeHtml(entry.date)}</td>
        <td>${escapeHtml(entry.message)}</td>
      </tr>
    `).join("")
    : `
      <tr>
        <td colspan="2" class="empty">No entries for this week</td>
      </tr>
    `;

  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>tart week ${escapeHtml(week.weekStart)}</title>
    <style>
      * { box-sizing: border-box; }
      body {
        margin: 0;
        padding: 34px;
        background: #ffffff;
        color: #17201d;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      header {
        border-bottom: 2px solid #286a5c;
        margin-bottom: 22px;
        padding-bottom: 16px;
      }
      h1 {
        margin: 0;
        font-size: 26px;
        line-height: 1.2;
      }
      p {
        margin: 8px 0 0;
        color: #65716d;
        font-size: 13px;
      }
      table {
        width: 100%;
        border-collapse: collapse;
      }
      th {
        background: #eef2ed;
        color: #1f5147;
        font-size: 12px;
        text-align: left;
        text-transform: uppercase;
      }
      th,
      td {
        border: 1px solid #d9ded8;
        padding: 10px 12px;
        vertical-align: top;
      }
      td:first-child {
        width: 112px;
        color: #1f5147;
        font-weight: 700;
        white-space: nowrap;
      }
      .empty {
        color: #65716d;
        font-style: italic;
        text-align: center;
      }
    </style>
  </head>
  <body>
    <header>
      <h1>tart weekly export</h1>
      <p>Week of ${escapeHtml(week.weekStart)}</p>
    </header>
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Message</th>
        </tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
  </body>
</html>`;
}

async function createWeekPdf(week) {
  const exportWindow = new BrowserWindow({
    height: 900,
    show: false,
    width: 720,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  try {
    await exportWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(buildWeekPdfHtml(week))}`);
    return await exportWindow.webContents.printToPDF({
      landscape: false,
      margins: {
        marginType: "default",
      },
      pageSize: "A4",
      printBackground: true,
    });
  } finally {
    exportWindow.destroy();
  }
}

async function exportWeek(formatValue) {
  const format = normalizeExportFormat(formatValue);
  const formatOptions = exportFormats[format];
  const week = await store.readWeek();
  const result = await dialog.showSaveDialog(mainWindow, {
    buttonLabel: "Export",
    defaultPath: defaultExportPath(week, format),
    filters: [
      {
        extensions: [formatOptions.extension],
        name: formatOptions.label,
      },
    ],
    title: `Export week as ${formatOptions.label}`,
  });

  if (result.canceled || !result.filePath) {
    return {
      canceled: true,
      format,
    };
  }

  if (format === "pdf") {
    await fsPromises.writeFile(result.filePath, await createWeekPdf(week));
  } else if (format === "csv") {
    await fsPromises.writeFile(result.filePath, formatEntriesAsCsv(week.entries), "utf8");
  } else {
    await fsPromises.writeFile(result.filePath, formatWeekAsPlainText(week), "utf8");
  }

  return {
    canceled: false,
    filePath: result.filePath,
    format,
    mimeType: formatOptions.mimeType,
  };
}

function serializeError(error) {
  if (error instanceof TartCoreError) {
    return { message: error.message, expected: true };
  }

  return {
    message: error && error.message ? error.message : "Unexpected desktop error",
    expected: false,
  };
}

async function handleDesktopAction(action) {
  try {
    return { ok: true, data: await action() };
  } catch (error) {
    return { ok: false, error: serializeError(error) };
  }
}

async function openLogDirectory() {
  await store.ensureLogDir();
  const result = await shell.openPath(store.logDir);

  if (result) {
    throw new TartCoreError(result);
  }

  return store.logDir;
}

app.whenReady().then(() => {
  if (process.platform === "win32") {
    app.setAppUserModelId("com.tart.desktop");
  }

  createStore();
  createTray();
  createWindow();

  app.on("activate", () => {
    showMainWindow();
  });
});

app.on("before-quit", () => {
  isQuitting = true;
});

app.on("window-all-closed", () => {
  if (isQuitting) {
    app.quit();
  }
});

ipcMain.handle("tart:get-state", () => handleDesktopAction(() => store.getState()));
ipcMain.handle("tart:add-entry", (_event, message) => handleDesktopAction(() => store.addEntry(message).then(() => store.getState())));
ipcMain.handle("tart:save-week", (_event, text) => handleDesktopAction(() => store.saveWeek("", text).then(() => store.getState())));
ipcMain.handle("tart:open-log-dir", () => handleDesktopAction(openLogDirectory));
ipcMain.handle("tart:export-week", (_event, format) => handleDesktopAction(() => exportWeek(format)));
