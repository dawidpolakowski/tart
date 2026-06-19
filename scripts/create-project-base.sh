#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Create a reusable Electron desktop project scaffold based on tart.

Usage:
  create-project-base.sh <project-name> [target-dir]

Examples:
  ./scripts/create-project-base.sh "Focus Journal"
  ./scripts/create-project-base.sh "Client Notes" /tmp/client-notes
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"
  value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  printf '%s\n' "$value"
}

write_text_file() {
  local path="$1"
  shift
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

replace_tokens() {
  local file="$1"
  local tmp_file="${file}.tmp"

  sed \
    -e "s/__APP_NAME__/${APP_NAME}/g" \
    -e "s/__APP_SLUG__/${APP_SLUG}/g" \
    -e "s/__APP_DESCRIPTION__/${APP_DESCRIPTION}/g" \
    "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

copy_icon_assets() {
  local source_dir="$1"
  local target_dir="$2"

  mkdir -p "$target_dir"
  cp "${source_dir}/tart-clock-icon.png" "${target_dir}/app-icon.png"

  if [[ -f "${source_dir}/tart-clock-icon.icns" ]]; then
    cp "${source_dir}/tart-clock-icon.icns" "${target_dir}/app-icon.icns"
  fi

  if [[ -f "${source_dir}/tart-clock-icon.ico" ]]; then
    cp "${source_dir}/tart-clock-icon.ico" "${target_dir}/app-icon.ico"
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if (($# < 1 || $# > 2)); then
  usage >&2
  exit 2
fi

APP_NAME="$(trim "$1")"

if [[ -z "$APP_NAME" ]]; then
  printf 'project name cannot be empty\n' >&2
  exit 2
fi

if [[ ! "${APP_NAME:0:1}" =~ [A-Za-z0-9] ]]; then
  printf 'project name may contain only letters, numbers, spaces, dot, underscore, and hyphen\n' >&2
  exit 2
fi

INVALID_CHARS="$(printf '%s' "$APP_NAME" | tr -d 'A-Za-z0-9._ -')"
if [[ -n "$INVALID_CHARS" ]]; then
  printf 'project name may contain only letters, numbers, spaces, dot, underscore, and hyphen\n' >&2
  exit 2
fi

APP_SLUG="$(slugify "$APP_NAME")"
if [[ -z "$APP_SLUG" ]]; then
  printf 'failed to derive project slug from %s\n' "$APP_NAME" >&2
  exit 2
fi

APP_DESCRIPTION="${APP_NAME} desktop starter generated from tart"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${2:-${ROOT_DIR}/${APP_SLUG}}"

if [[ -e "$TARGET_DIR" && -n "$(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  printf 'target directory is not empty: %s\n' "$TARGET_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"/desktop "$TARGET_DIR"/assets

write_text_file "$TARGET_DIR/.gitignore" <<'EOF'
node_modules
.DS_Store
dist
release
EOF

write_text_file "$TARGET_DIR/package.json" <<'EOF'
{
  "name": "__APP_SLUG__",
  "version": "0.1.0",
  "description": "__APP_DESCRIPTION__",
  "license": "MIT",
  "main": "desktop/main.cjs",
  "scripts": {
    "desktop": "electron .",
    "start": "npm run desktop"
  },
  "engines": {
    "node": ">=20"
  },
  "devDependencies": {
    "electron": "^42.4.1"
  }
}
EOF

write_text_file "$TARGET_DIR/README.md" <<'EOF'
# __APP_NAME__

This project starter was generated from `tart`.

It gives you a solid Electron desktop base with:

* tray or menu-bar presence
* local file-backed weekly activity data
* add, review, edit, and export flows
* a preload bridge pattern for renderer isolation
* a clean structure you can keep or replace incrementally

## Quick Start

```bash
npm install
npm run desktop
```

## Structure

```text
assets/         Icons used for the window and tray
desktop/        Electron main, preload, renderer, styles, and HTML
package.json    App scripts and Electron dependency
```

## Default Data Location

The starter stores logs in:

```text
~/Documents/__APP_SLUG__
```

## What To Customize First

1. Replace the icon files in `assets/`.
2. Update the copy in `desktop/index.html`.
3. Replace `desktop/app-core.cjs` if your project needs a different storage model.
4. Adjust export behavior in `desktop/main.cjs`.

## Notes

The scaffold intentionally keeps the file-backed weekly log model from tart so you can start from a working desktop app instead of an empty Electron shell.
EOF

write_text_file "$TARGET_DIR/desktop/app-core.cjs" <<'EOF'
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const DATE_PATTERN = /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
const ISO_WEEK_PATTERN = /^([0-9]{4})-W([0-9]{2})$/;
const DAY_MS = 24 * 60 * 60 * 1000;

class AppCoreError extends Error {
  constructor(message) {
    super(message);
    this.name = "AppCoreError";
  }
}

function defaultDataDir(homeDir = os.homedir()) {
  return path.join(homeDir, "Documents", "__APP_SLUG__");
}

function pad2(value) {
  return String(value).padStart(2, "0");
}

function formatUtcDate(date) {
  return `${date.getUTCFullYear()}-${pad2(date.getUTCMonth() + 1)}-${pad2(date.getUTCDate())}`;
}

function formatLocalDate(date = new Date()) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

function parseDateLiteral(value) {
  const match = DATE_PATTERN.exec(value || "");

  if (!match) {
    throw new AppCoreError(`invalid date: ${value}`);
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));

  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new AppCoreError(`invalid date: ${value}`);
  }

  return date;
}

function weekStartForDate(value) {
  const date = parseDateLiteral(value);
  const isoDay = date.getUTCDay() === 0 ? 7 : date.getUTCDay();
  const weekStart = new Date(date.getTime() - (isoDay - 1) * DAY_MS);
  return formatUtcDate(weekStart);
}

function isoWeekForDate(value) {
  const date = parseDateLiteral(value);
  const isoDay = date.getUTCDay() === 0 ? 7 : date.getUTCDay();
  const thursday = new Date(date.getTime() + (4 - isoDay) * DAY_MS);
  const isoYear = thursday.getUTCFullYear();
  const jan4 = new Date(Date.UTC(isoYear, 0, 4));
  const jan4IsoDay = jan4.getUTCDay() === 0 ? 7 : jan4.getUTCDay();
  const firstMonday = new Date(jan4.getTime() - (jan4IsoDay - 1) * DAY_MS);
  const currentMonday = new Date(parseDateLiteral(weekStartForDate(value)).getTime());
  const weekNumber = Math.floor((currentMonday.getTime() - firstMonday.getTime()) / (7 * DAY_MS)) + 1;
  return `${isoYear}-W${pad2(weekNumber)}`;
}

function weekStartForIsoWeek(value) {
  const match = ISO_WEEK_PATTERN.exec(value || "");

  if (!match) {
    throw new AppCoreError(`invalid ISO week: ${value}`);
  }

  const isoYear = Number(match[1]);
  const isoWeek = Number(match[2]);

  if (isoWeek < 1 || isoWeek > 53) {
    throw new AppCoreError(`invalid ISO week: ${value}`);
  }

  const jan4 = new Date(Date.UTC(isoYear, 0, 4));
  const jan4IsoDay = jan4.getUTCDay() === 0 ? 7 : jan4.getUTCDay();
  const firstMonday = new Date(jan4.getTime() - (jan4IsoDay - 1) * DAY_MS);
  const weekStart = new Date(firstMonday.getTime() + (isoWeek - 1) * 7 * DAY_MS);
  const weekStartText = formatUtcDate(weekStart);

  if (isoWeekForDate(weekStartText) !== value) {
    throw new AppCoreError(`invalid ISO week: ${value}`);
  }

  return weekStartText;
}

function weekStartFromRef(ref, today = formatLocalDate()) {
  const value = ref || today;

  if (DATE_PATTERN.test(value)) {
    return weekStartForDate(value);
  }

  if (ISO_WEEK_PATTERN.test(value)) {
    return weekStartForIsoWeek(value);
  }

  throw new AppCoreError(`invalid week reference: ${value}`);
}

function normalizeLogText(text) {
  const normalized = String(text || "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\n+$/, "");
  return normalized ? `${normalized}\n` : "";
}

function parseEntries(text) {
  return normalizeLogText(text)
    .split("\n")
    .filter(Boolean)
    .map((line, index) => ({
      id: `${index}-${line}`,
      date: line.slice(0, 10),
      message: line.slice(11),
      line,
    }));
}

function escapeCsvCell(value) {
  const text = String(value ?? "");

  if (!/[",\n\r]/.test(text)) {
    return text;
  }

  return `"${text.replace(/"/g, '""')}"`;
}

function formatEntriesAsCsv(entries) {
  const rows = [["date", "message"]];

  for (const entry of entries || []) {
    rows.push([entry && entry.date ? entry.date : "", entry && entry.message ? entry.message : ""]);
  }

  return `${rows.map((row) => row.map(escapeCsvCell).join(",")).join("\n")}\n`;
}

class ActivityStore {
  constructor(options = {}) {
    this.env = options.env || process.env;
    this.logDir = options.logDir || this.env.APP_LOGDIR || defaultDataDir(options.homeDir);
    this.todayOverride = options.today || this.env.APP_TODAY || "";
  }

  todayDate() {
    if (!this.todayOverride) {
      return formatLocalDate();
    }

    parseDateLiteral(this.todayOverride);
    return this.todayOverride;
  }

  weekStart(ref = "") {
    return weekStartFromRef(ref, this.todayDate());
  }

  weekPath(ref = "") {
    return path.join(this.logDir, `${this.weekStart(ref)}.log`);
  }

  async ensureLogDir() {
    await fs.mkdir(this.logDir, { recursive: true });
  }

  async readTextIfExists(filePath) {
    try {
      return await fs.readFile(filePath, "utf8");
    } catch (error) {
      if (error && error.code === "ENOENT") {
        return "";
      }
      throw error;
    }
  }

  async addEntry(message) {
    const cleanMessage = String(message || "").trim();

    if (!cleanMessage) {
      throw new AppCoreError("missing entry message");
    }

    if (cleanMessage.includes("\n") || cleanMessage.includes("\r")) {
      throw new AppCoreError("entry message must be a single line");
    }

    const today = this.todayDate();
    const filePath = this.weekPath(today);
    const line = `${today} ${cleanMessage}`;

    await this.ensureLogDir();
    await fs.appendFile(filePath, `${line}\n`, "utf8");

    return { date: today, message: cleanMessage, line, filePath };
  }

  async readWeek(ref = "") {
    const weekStart = this.weekStart(ref);
    const filePath = this.weekPath(weekStart);
    const text = await this.readTextIfExists(filePath);

    return {
      weekStart,
      filePath,
      text: normalizeLogText(text),
      entries: parseEntries(text),
    };
  }

  async readToday() {
    const today = this.todayDate();
    const week = await this.readWeek(today);

    return {
      date: today,
      entries: week.entries.filter((entry) => entry.date === today),
    };
  }

  async saveWeek(ref, text) {
    const weekStart = this.weekStart(ref || "");
    const filePath = this.weekPath(weekStart);

    await this.ensureLogDir();
    await fs.writeFile(filePath, normalizeLogText(text), "utf8");

    return this.readWeek(weekStart);
  }

  async getState(ref = "") {
    const week = await this.readWeek(ref);
    const today = await this.readToday();

    return {
      config: {
        logDir: this.logDir,
        currentFile: this.weekPath(this.todayDate()),
      },
      today,
      week,
    };
  }
}

module.exports = {
  ActivityStore,
  AppCoreError,
  defaultDataDir,
  formatEntriesAsCsv,
  normalizeLogText,
  parseEntries,
};
EOF

write_text_file "$TARGET_DIR/desktop/main.cjs" <<'EOF'
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
    title: "__APP_NAME__",
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
  tray.setToolTip("__APP_NAME__");
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Show __APP_NAME__", click: showMainWindow },
    { label: "Open data directory", click: () => handleDesktopAction(openLogDirectory) },
    { type: "separator" },
    {
      label: "Quit __APP_NAME__",
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
    app.setAppUserModelId("com.__APP_SLUG__.desktop");
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
EOF

write_text_file "$TARGET_DIR/desktop/preload.cjs" <<'EOF'
const { contextBridge, ipcRenderer } = require("electron");

async function invoke(channel, ...args) {
  const response = await ipcRenderer.invoke(channel, ...args);

  if (!response.ok) {
    const error = new Error(response.error.message);
    error.expected = response.error.expected;
    throw error;
  }

  return response.data;
}

contextBridge.exposeInMainWorld("appApi", {
  addEntry: (message) => invoke("app:add-entry", message),
  exportWeek: (format) => invoke("app:export-week", format),
  getState: () => invoke("app:get-state"),
  openLogDir: () => invoke("app:open-log-dir"),
  saveWeek: (text) => invoke("app:save-week", text),
});
EOF

write_text_file "$TARGET_DIR/desktop/renderer.cjs" <<'EOF'
const viewTitles = {
  week: "This week",
  today: "Today",
  edit: "Edit weekly file",
};

function collectElements(documentRef) {
  return {
    entryForm: documentRef.querySelector("#entryForm"),
    entryInput: documentRef.querySelector("#entryInput"),
    exportButtons: Array.from(documentRef.querySelectorAll(".export-button")),
    logDir: documentRef.querySelector("#logDir"),
    openLogDirButton: documentRef.querySelector("#openLogDirButton"),
    referenceInput: documentRef.querySelector("#referenceInput"),
    refreshButton: documentRef.querySelector("#refreshButton"),
    saveWeekButton: documentRef.querySelector("#saveWeekButton"),
    status: documentRef.querySelector("#status"),
    tabs: Array.from(documentRef.querySelectorAll(".tab")),
    todayCount: documentRef.querySelector("#todayCount"),
    todayDate: documentRef.querySelector("#todayDate"),
    todayEntries: documentRef.querySelector("#todayEntries"),
    viewTitle: documentRef.querySelector("#viewTitle"),
    views: Array.from(documentRef.querySelectorAll(".view")),
    weekCount: documentRef.querySelector("#weekCount"),
    weekEditor: documentRef.querySelector("#weekEditor"),
    weekEntries: documentRef.querySelector("#weekEntries"),
    weekFile: documentRef.querySelector("#weekFile"),
    weekLabel: documentRef.querySelector("#weekLabel"),
  };
}

function buildEntryMessage(message, reference) {
  const cleanMessage = String(message || "").trim();
  const cleanReference = String(reference || "").trim();

  if (!cleanReference) {
    return cleanMessage;
  }

  return `${cleanMessage} [ref: ${cleanReference}]`;
}

function createDesktopRenderer({ document: documentRef, api, initialView = "week" }) {
  const elements = collectElements(documentRef);
  let currentState = null;
  let currentView = initialView;

  function setStatus(message, tone = "") {
    elements.status.textContent = message || "";
    elements.status.dataset.tone = tone;
  }

  function setBusy(isBusy) {
    elements.entryInput.disabled = isBusy;
    elements.referenceInput.disabled = isBusy;
    elements.refreshButton.disabled = isBusy;
    elements.saveWeekButton.disabled = isBusy;

    for (const button of elements.exportButtons) {
      button.disabled = isBusy;
    }
  }

  function showView(view) {
    currentView = view;
    elements.viewTitle.textContent = viewTitles[view];

    for (const tab of elements.tabs) {
      tab.classList.toggle("is-active", tab.dataset.view === view);
    }

    for (const panel of elements.views) {
      panel.classList.toggle("is-active", panel.id === `${view}View`);
    }
  }

  function renderEntries(container, entries, emptyText) {
    container.replaceChildren();

    if (!entries.length) {
      const empty = documentRef.createElement("div");
      empty.className = "empty-state";
      empty.textContent = emptyText;
      container.append(empty);
      return;
    }

    for (const entry of entries) {
      const row = documentRef.createElement("article");
      row.className = "entry";

      const date = documentRef.createElement("div");
      date.className = "entry__date";
      date.textContent = entry.date;

      const message = documentRef.createElement("div");
      message.className = "entry__message";
      message.textContent = entry.message;

      row.append(date, message);
      container.append(row);
    }
  }

  function renderState(state) {
    currentState = state;
    elements.weekLabel.textContent = `Week of ${state.week.weekStart}`;
    elements.weekCount.textContent = String(state.week.entries.length);
    elements.todayCount.textContent = String(state.today.entries.length);
    elements.logDir.textContent = state.config.logDir;
    elements.weekFile.textContent = state.week.filePath;
    elements.todayDate.textContent = state.today.date;
    elements.weekEditor.value = state.week.text;

    renderEntries(elements.weekEntries, state.week.entries, "No entries for this week");
    renderEntries(elements.todayEntries, state.today.entries, "No entries for today");
  }

  async function loadState() {
    setBusy(true);

    try {
      renderState(await api.getState());
      setStatus("");
    } catch (error) {
      setStatus(error.message, "error");
    } finally {
      setBusy(false);
    }
  }

  async function addEntry(event) {
    event.preventDefault();
    const message = elements.entryInput.value.trim();
    const reference = elements.referenceInput.value.trim();

    if (!message) {
      setStatus("Enter a log message.", "error");
      elements.entryInput.focus();
      return;
    }

    if (reference.includes("\n") || reference.includes("\r")) {
      setStatus("Ticket or link must be a single line.", "error");
      elements.referenceInput.focus();
      return;
    }

    setBusy(true);

    try {
      renderState(await api.addEntry(buildEntryMessage(message, reference)));
      elements.entryInput.value = "";
      elements.referenceInput.value = "";
      setStatus("Entry added.", "ok");
      showView("week");
    } catch (error) {
      setStatus(error.message, "error");
    } finally {
      setBusy(false);
    }
  }

  async function saveWeek() {
    setBusy(true);

    try {
      renderState(await api.saveWeek(elements.weekEditor.value));
      setStatus("Weekly file saved.", "ok");
      showView("week");
    } catch (error) {
      setStatus(error.message, "error");
    } finally {
      setBusy(false);
    }
  }

  async function openLogDir() {
    try {
      await api.openLogDir();
    } catch (error) {
      setStatus(error.message, "error");
    }
  }

  async function exportWeek(format) {
    setBusy(true);

    try {
      const result = await api.exportWeek(format);

      if (result && result.canceled) {
        setStatus("");
        return;
      }

      const label = String(format).toUpperCase();
      setStatus(`Exported ${label} week.`, "ok");
    } catch (error) {
      setStatus(error.message, "error");
    } finally {
      setBusy(false);
    }
  }

  function bindEvents() {
    for (const tab of elements.tabs) {
      tab.addEventListener("click", () => showView(tab.dataset.view));
    }

    for (const button of elements.exportButtons) {
      button.addEventListener("click", () => exportWeek(button.dataset.format));
    }

    elements.entryForm.addEventListener("submit", addEntry);
    elements.refreshButton.addEventListener("click", loadState);
    elements.saveWeekButton.addEventListener("click", saveWeek);
    elements.openLogDirButton.addEventListener("click", openLogDir);
  }

  function start() {
    bindEvents();
    showView(currentView);
    return loadState();
  }

  return {
    start,
  };
}

if (typeof window !== "undefined" && window.document && window.appApi) {
  createDesktopRenderer({
    api: window.appApi,
    document: window.document,
  }).start();
}

if (typeof module !== "undefined") {
  module.exports = {
    buildEntryMessage,
    collectElements,
    createDesktopRenderer,
    viewTitles,
  };
}
EOF

write_text_file "$TARGET_DIR/desktop/index.html" <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>__APP_NAME__</title>
    <link rel="stylesheet" href="./styles.css">
  </head>
  <body>
    <div class="app-shell">
      <aside class="sidebar">
        <div class="brand">
          <img class="brand__icon" src="../assets/app-icon.png" alt="">
          <div>
            <h1>__APP_NAME__</h1>
            <p id="weekLabel">Loading</p>
          </div>
        </div>

        <div class="stats">
          <div class="stat">
            <span class="stat__value" id="weekCount">0</span>
            <span class="stat__label">Week</span>
          </div>
          <div class="stat">
            <span class="stat__value" id="todayCount">0</span>
            <span class="stat__label">Today</span>
          </div>
        </div>

        <nav class="tabs" aria-label="Views">
          <button class="tab is-active" data-view="week" type="button">Week</button>
          <button class="tab" data-view="today" type="button">Today</button>
          <button class="tab" data-view="edit" type="button">Edit</button>
        </nav>

        <div class="log-location">
          <span>Data directory</span>
          <button id="openLogDirButton" type="button">Open</button>
        </div>
        <p class="path" id="logDir">-</p>
      </aside>

      <main class="workspace">
        <header class="topbar">
          <div>
            <p class="eyebrow">__APP_DESCRIPTION__</p>
            <h2 id="viewTitle">This week</h2>
          </div>
          <div class="topbar__actions">
            <div class="export-actions">
              <span>Export</span>
              <button class="ghost-button export-button" data-format="txt" type="button">TXT</button>
              <button class="ghost-button export-button" data-format="csv" type="button">CSV</button>
            </div>
            <button class="ghost-button" id="refreshButton" type="button">Refresh</button>
          </div>
        </header>

        <form class="entry-form" id="entryForm">
          <input id="entryInput" name="entry" autocomplete="off" maxlength="240" placeholder="What happened today?">
          <input id="referenceInput" name="reference" autocomplete="off" maxlength="180" placeholder="Optional ticket or link">
          <button type="submit">+ Add</button>
        </form>

        <p class="status" id="status" role="status"></p>

        <section class="view is-active" id="weekView">
          <div class="section-heading">
            <h3>Weekly log</h3>
            <span id="weekFile">-</span>
          </div>
          <div class="entries" id="weekEntries"></div>
        </section>

        <section class="view" id="todayView">
          <div class="section-heading">
            <h3>Today</h3>
            <span id="todayDate">-</span>
          </div>
          <div class="entries" id="todayEntries"></div>
        </section>

        <section class="view" id="editView">
          <div class="section-heading">
            <h3>Raw weekly file</h3>
            <button class="save-button" id="saveWeekButton" type="button">Save</button>
          </div>
          <textarea id="weekEditor" spellcheck="false"></textarea>
        </section>
      </main>
    </div>

    <script src="./renderer.cjs"></script>
  </body>
</html>
EOF

write_text_file "$TARGET_DIR/desktop/styles.css" <<'EOF'
:root {
  color-scheme: light;
  --bg: #f5f4ef;
  --panel: #ffffff;
  --panel-soft: #f1ede4;
  --ink: #191714;
  --muted: #746c60;
  --line: #ddd6cb;
  --accent: #2f6657;
  --accent-dark: #21493f;
  --warn: #bb5843;
  --shadow: 0 22px 48px rgba(25, 23, 20, 0.12);
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  min-width: 920px;
  min-height: 640px;
  overflow: hidden;
  background: var(--bg);
  color: var(--ink);
  font-family: "Avenir Next", Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

button,
input,
textarea {
  font: inherit;
}

button {
  border: 0;
  cursor: pointer;
}

.app-shell {
  display: grid;
  grid-template-columns: 300px minmax(0, 1fr);
  height: 100vh;
}

.sidebar {
  display: flex;
  flex-direction: column;
  gap: 22px;
  padding: 28px 22px;
  background: #fbf8f1;
  border-right: 1px solid var(--line);
}

.brand {
  display: grid;
  grid-template-columns: 58px minmax(0, 1fr);
  gap: 14px;
  align-items: center;
}

.brand__icon {
  width: 58px;
  height: 58px;
  border-radius: 14px;
  object-fit: cover;
  box-shadow: 0 10px 26px rgba(47, 102, 87, 0.18);
}

h1,
h2,
h3,
p {
  margin: 0;
}

h1 {
  font-size: 28px;
  line-height: 1;
}

.brand p,
.path,
.stat__label,
.eyebrow,
.section-heading span,
.status {
  color: var(--muted);
}

.brand p {
  margin-top: 6px;
  font-size: 13px;
}

.stats {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

.stat {
  border: 1px solid var(--line);
  border-radius: 14px;
  background: var(--panel);
  padding: 14px;
}

.stat__value {
  display: block;
  font-size: 28px;
  font-weight: 760;
  line-height: 1;
}

.stat__label {
  display: block;
  margin-top: 8px;
  font-size: 12px;
  text-transform: uppercase;
}

.tabs {
  display: grid;
  gap: 8px;
}

.tab {
  height: 44px;
  border-radius: 12px;
  background: transparent;
  color: var(--ink);
  text-align: left;
  padding: 0 14px;
}

.tab:hover,
.tab.is-active {
  background: var(--panel-soft);
}

.tab.is-active {
  color: var(--accent-dark);
  font-weight: 720;
}

.log-location {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: auto;
  font-size: 13px;
  font-weight: 700;
}

.log-location button,
.ghost-button,
.save-button {
  height: 36px;
  border-radius: 12px;
  border: 1px solid var(--line);
  background: var(--panel);
  color: var(--ink);
  padding: 0 12px;
}

.path {
  overflow-wrap: anywhere;
  font-size: 12px;
  line-height: 1.45;
}

.workspace {
  display: grid;
  grid-template-rows: auto auto auto minmax(0, 1fr);
  gap: 18px;
  min-width: 0;
  padding: 30px;
}

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
}

.eyebrow {
  margin-bottom: 8px;
  font-size: 12px;
  font-weight: 760;
  text-transform: uppercase;
}

h2 {
  font-size: 34px;
  line-height: 1.1;
}

.topbar__actions,
.export-actions {
  display: flex;
  align-items: center;
  gap: 10px;
}

.export-actions span {
  color: var(--muted);
  font-size: 12px;
  font-weight: 760;
  text-transform: uppercase;
}

.entry-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 220px 112px;
  gap: 10px;
}

.entry-form input,
textarea {
  border: 1px solid var(--line);
  border-radius: 14px;
  background: var(--panel);
  color: var(--ink);
  outline: none;
}

.entry-form input {
  height: 48px;
  padding: 0 16px;
}

.entry-form input:focus,
textarea:focus {
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(47, 102, 87, 0.14);
}

.entry-form button {
  height: 48px;
  border-radius: 14px;
  background: var(--accent);
  color: #ffffff;
  font-weight: 760;
}

.entry-form button:hover {
  background: var(--accent-dark);
}

.status {
  min-height: 20px;
  font-size: 13px;
}

.status[data-tone="ok"] {
  color: var(--accent-dark);
}

.status[data-tone="error"] {
  color: var(--warn);
}

.view {
  display: none;
  min-height: 0;
}

.view.is-active {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  gap: 12px;
}

.section-heading {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
}

.section-heading h3 {
  font-size: 18px;
}

.entries,
textarea {
  min-height: 0;
  border: 1px solid var(--line);
  border-radius: 18px;
  background: var(--panel);
  box-shadow: var(--shadow);
}

.entries {
  display: grid;
  align-content: start;
  gap: 10px;
  overflow: auto;
  padding: 18px;
}

.entry {
  display: grid;
  grid-template-columns: 116px minmax(0, 1fr);
  gap: 14px;
  border-bottom: 1px solid var(--line);
  padding-bottom: 10px;
}

.entry:last-child {
  border-bottom: 0;
  padding-bottom: 0;
}

.entry__date {
  color: var(--accent-dark);
  font-weight: 760;
}

.entry__message {
  line-height: 1.5;
  white-space: pre-wrap;
}

.empty-state {
  color: var(--muted);
  font-style: italic;
}

textarea {
  width: 100%;
  resize: none;
  padding: 18px;
  font-family: "SF Mono", "Cascadia Code", Consolas, monospace;
  font-size: 13px;
}
EOF

copy_icon_assets "${ROOT_DIR}/assets" "${TARGET_DIR}/assets"

while IFS= read -r -d '' file; do
  replace_tokens "$file"
done < <(find "$TARGET_DIR" -type f \( -name "*.md" -o -name "*.json" -o -name "*.cjs" -o -name "*.html" \) -print0)

printf 'Created project base at %s\n' "$TARGET_DIR"
printf 'Next steps:\n'
printf '  cd %s\n' "$TARGET_DIR"
printf '  npm install\n'
printf '  npm run desktop\n'
