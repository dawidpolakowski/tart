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
