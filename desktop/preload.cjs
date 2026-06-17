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

contextBridge.exposeInMainWorld("tart", {
  addEntry: (message) => invoke("tart:add-entry", message),
  exportWeek: (format) => invoke("tart:export-week", format),
  getState: () => invoke("tart:get-state"),
  openLogDir: () => invoke("tart:open-log-dir"),
  saveWeek: (text) => invoke("tart:save-week", text),
});
