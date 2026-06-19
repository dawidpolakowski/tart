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
