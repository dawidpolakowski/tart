const path = require("node:path");
const fs = require("node:fs");
const fsPromises = require("node:fs/promises");
const { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, shell, Tray } = require("electron");
const { ActivityStore, AppCoreError, formatEntriesAsCsv, normalizeLogText } = require("./app-core.cjs");

let mainWindow = null;
let tray = null;
let store = null;
let isQuitting = false;

const exportFormats = {
  csv: { extension: "csv", label: "CSV", mimeType: "text/csv" },
  txt: { extension: "txt", label: "Plain Text", mimeType: "text/plain" },
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
  return assetPath("app-icon.png");
}

function appIconPath() {
  if (process.platform === "darwin") {
    return firstExistingAsset(["app-icon.icns", "app-icon.png"]);
  }
  if (process.platform === "win32") {
    return firstExistingAsset(["app-icon.ico", "app-icon.png"]);
  }
  return firstExistingAsset(["app-icon.png"]);
}

function trayIcon() {
  const size = process.platform === "darwin" ? 18 : 16;
  return nativeImage.createFromPath(assetPath("app-icon.png")).resize({ width: size, height: size });
}

function createStore() {
  store = new ActivityStore();
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
    width: 1100,
    height: 760,
    minWidth: 920,
    minHeight: 640,
    title: "TART",
    backgroundColor: "#f5f4ef",
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
  tray.setToolTip("TART");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Show TART", click: showMainWindow },
    { label: "Open data directory", click: () => handleDesktopAction(openLogDirectory) },
    { type: "separator" },
    {
      label: "Quit TART",
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ]));

  tray.on("click", showMainWindow);
  tray.on("double-click", showMainWindow);
}

function serializeError(error) {
  if (error instanceof AppCoreError) {
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
    throw new AppCoreError(result);
  }

  return store.logDir;
}

function defaultExportPath(week, format) {
  const options = exportFormats[format];
  return path.join(app.getPath("documents"), `${week.weekStart}.${options.extension}`);
}

async function exportWeek(formatValue) {
  const format = String(formatValue || "").toLowerCase();

  if (!Object.hasOwn(exportFormats, format)) {
    throw new AppCoreError(`unsupported export format: ${formatValue}`);
  }

  const week = await store.readWeek();
  const formatOptions = exportFormats[format];
  const result = await dialog.showSaveDialog(mainWindow, {
    buttonLabel: "Export",
    defaultPath: defaultExportPath(week, format),
    filters: [{ name: formatOptions.label, extensions: [formatOptions.extension] }],
    title: `Export week as ${formatOptions.label}`,
  });

  if (result.canceled || !result.filePath) {
    return { canceled: true, format };
  }

  if (format === "csv") {
    await fsPromises.writeFile(result.filePath, formatEntriesAsCsv(week.entries), "utf8");
  } else {
    await fsPromises.writeFile(result.filePath, normalizeLogText(week.text), "utf8");
  }

  return {
    canceled: false,
    filePath: result.filePath,
    format,
    mimeType: formatOptions.mimeType,
  };
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

ipcMain.handle("app:get-state", () => handleDesktopAction(() => store.getState()));
ipcMain.handle("app:add-entry", (_event, message) => handleDesktopAction(() => store.addEntry(message).then(() => store.getState())));
ipcMain.handle("app:save-week", (_event, text) => handleDesktopAction(() => store.saveWeek("", text).then(() => store.getState())));
ipcMain.handle("app:open-log-dir", () => handleDesktopAction(openLogDirectory));
ipcMain.handle("app:export-week", (_event, format) => handleDesktopAction(() => exportWeek(format)));
