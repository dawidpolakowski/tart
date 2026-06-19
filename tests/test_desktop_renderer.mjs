import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { buildEntryMessage, createTartRenderer } = require("../desktop/renderer.cjs");

class FakeClassList {
  constructor(element) {
    this.element = element;
    this.classes = new Set((element.className || "").split(/\s+/).filter(Boolean));
  }

  contains(className) {
    return this.classes.has(className);
  }

  toggle(className, force) {
    const shouldAdd = force === undefined ? !this.classes.has(className) : Boolean(force);

    if (shouldAdd) {
      this.classes.add(className);
    } else {
      this.classes.delete(className);
    }

    this.element.className = Array.from(this.classes).join(" ");
    return shouldAdd;
  }
}

class FakeElement {
  constructor({ id = "", className = "", dataset = {} } = {}) {
    this.id = id;
    this.className = className;
    this.dataset = { ...dataset };
    this.textContent = "";
    this.value = "";
    this.disabled = false;
    this.children = [];
    this.listeners = {};
    this.focusCount = 0;
    this.classList = new FakeClassList(this);
  }

  addEventListener(eventName, callback) {
    this.listeners[eventName] = callback;
  }

  append(...children) {
    this.children.push(...children);
  }

  focus() {
    this.focusCount += 1;
  }

  replaceChildren(...children) {
    this.children = [...children];
  }
}

class FakeDocument {
  constructor() {
    this.elements = new Map();
    this.tabs = [
      new FakeElement({ className: "tab is-active", dataset: { view: "week" } }),
      new FakeElement({ className: "tab", dataset: { view: "today" } }),
      new FakeElement({ className: "tab", dataset: { view: "edit" } }),
    ];
    this.exportButtons = [
      new FakeElement({ className: "ghost-button export-button", dataset: { format: "txt" } }),
      new FakeElement({ className: "ghost-button export-button", dataset: { format: "csv" } }),
      new FakeElement({ className: "ghost-button export-button", dataset: { format: "pdf" } }),
    ];
    this.views = [
      new FakeElement({ id: "weekView", className: "view is-active" }),
      new FakeElement({ id: "todayView", className: "view" }),
      new FakeElement({ id: "editView", className: "view" }),
    ];

    for (const id of [
      "entryForm",
      "entryInput",
      "logDir",
      "openLogDirButton",
      "referenceInput",
      "refreshButton",
      "saveWeekButton",
      "status",
      "todayCount",
      "todayDate",
      "todayEntries",
      "viewTitle",
      "weekCount",
      "weekEditor",
      "weekEntries",
      "weekFile",
      "weekLabel",
    ]) {
      this.elements.set(`#${id}`, new FakeElement({ id }));
    }
  }

  createElement() {
    return new FakeElement();
  }

  querySelector(selector) {
    return this.elements.get(selector) || null;
  }

  querySelectorAll(selector) {
    if (selector === ".tab") {
      return this.tabs;
    }

    if (selector === ".export-button") {
      return this.exportButtons;
    }

    if (selector === ".view") {
      return this.views;
    }

    return [];
  }
}

function makeState(overrides = {}) {
  return {
    config: {
      currentFile: "/tmp/tart/2026-04-27.log",
      logDir: "/tmp/tart",
    },
    today: {
      date: "2026-04-30",
      entries: [
        {
          date: "2026-04-30",
          message: "current day",
        },
      ],
    },
    week: {
      entries: [
        {
          date: "2026-04-29",
          message: "previous day",
        },
        {
          date: "2026-04-30",
          message: "current day",
        },
      ],
      filePath: "/tmp/tart/2026-04-27.log",
      text: "2026-04-29 previous day\n2026-04-30 current day\n",
      weekStart: "2026-04-27",
    },
    ...overrides,
  };
}

function makeRenderer(apiOverrides = {}) {
  const document = new FakeDocument();
  const calls = [];
  const api = {
    addEntry: async (message) => {
      calls.push(["addEntry", message]);
      return makeState({
        today: {
          date: "2026-04-30",
          entries: [{ date: "2026-04-30", message }],
        },
        week: {
          entries: [{ date: "2026-04-30", message }],
          filePath: "/tmp/tart/2026-04-27.log",
          text: `2026-04-30 ${message}\n`,
          weekStart: "2026-04-27",
        },
      });
    },
    getState: async () => {
      calls.push(["getState"]);
      return makeState();
    },
    exportWeek: async (format) => {
      calls.push(["exportWeek", format]);
      return {
        canceled: false,
        filePath: `/tmp/tart/week.${format}`,
        format,
      };
    },
    openLogDir: async () => {
      calls.push(["openLogDir"]);
      return "/tmp/tart";
    },
    saveWeek: async (text) => {
      calls.push(["saveWeek", text]);
      return makeState({
        week: {
          entries: [{ date: "2026-04-30", message: "saved" }],
          filePath: "/tmp/tart/2026-04-27.log",
          text,
          weekStart: "2026-04-27",
        },
      });
    },
    ...apiOverrides,
  };

  return {
    api,
    calls,
    document,
    renderer: createTartRenderer({ api, document }),
  };
}

let passCount = 0;
let failCount = 0;

async function runTest(name, fn) {
  process.stdout.write(`test ${name.padEnd(48, " ")}`);

  try {
    await fn();
    passCount += 1;
    process.stdout.write("ok\n");
  } catch (error) {
    failCount += 1;
    process.stdout.write("FAIL\n");
    process.stderr.write(`${error.stack || error.message}\n`);
  }
}

await runTest("renderer starts and paints initial state", async () => {
  const { calls, renderer } = makeRenderer();

  await renderer.start();

  assert.deepEqual(calls, [["getState"]]);
  assert.equal(renderer.elements.viewTitle.textContent, "This week");
  assert.equal(renderer.elements.weekLabel.textContent, "Week of 2026-04-27");
  assert.equal(renderer.elements.weekCount.textContent, "2");
  assert.equal(renderer.elements.todayCount.textContent, "1");
  assert.equal(renderer.elements.logDir.textContent, "/tmp/tart");
  assert.equal(renderer.elements.weekEntries.children.length, 2);
  assert.equal(renderer.elements.todayEntries.children.length, 1);
});

await runTest("renderer switches views", () => {
  const { document, renderer } = makeRenderer();

  renderer.showView("edit");

  assert.equal(renderer.getCurrentView(), "edit");
  assert.equal(renderer.elements.viewTitle.textContent, "Edit weekly file");
  assert.equal(document.tabs[2].classList.contains("is-active"), true);
  assert.equal(document.views[2].classList.contains("is-active"), true);
  assert.equal(document.views[0].classList.contains("is-active"), false);
});

await runTest("renderer shows empty states", () => {
  const { renderer } = makeRenderer();

  renderer.renderState(makeState({
    today: { date: "2026-04-30", entries: [] },
    week: {
      entries: [],
      filePath: "/tmp/tart/2026-04-27.log",
      text: "",
      weekStart: "2026-04-27",
    },
  }));

  assert.equal(renderer.elements.weekEntries.children.length, 1);
  assert.equal(renderer.elements.weekEntries.children[0].className, "empty-state");
  assert.equal(renderer.elements.weekEntries.children[0].textContent, "No entries for this week");
  assert.equal(renderer.elements.todayEntries.children[0].textContent, "No entries for today");
});

await runTest("renderer adds trimmed entries", async () => {
  const { calls, renderer } = makeRenderer();
  renderer.elements.entryInput.value = "  shipped electron app  ";

  await renderer.addEntry({ preventDefault() {} });

  assert.deepEqual(calls, [["addEntry", "shipped electron app"]]);
  assert.equal(renderer.elements.entryInput.value, "");
  assert.equal(renderer.elements.status.textContent, "Entry added.");
  assert.equal(renderer.elements.status.dataset.tone, "ok");
  assert.equal(renderer.getCurrentView(), "week");
  assert.equal(renderer.elements.weekEntries.children[0].children[1].textContent, "shipped electron app");
});

await runTest("renderer appends ticket or link references", async () => {
  const { calls, renderer } = makeRenderer();
  renderer.elements.entryInput.value = "Updated invoice workflow";
  renderer.elements.referenceInput.value = " CGI-123 ";

  await renderer.addEntry({ preventDefault() {} });

  assert.deepEqual(calls, [["addEntry", "Updated invoice workflow [ref: CGI-123]"]]);
  assert.equal(renderer.elements.entryInput.value, "");
  assert.equal(renderer.elements.referenceInput.value, "");
  assert.equal(renderer.elements.weekEntries.children[0].children[1].textContent, "Updated invoice workflow [ref: CGI-123]");
});

await runTest("renderer builds reference messages", () => {
  assert.equal(buildEntryMessage("Fixed reports", ""), "Fixed reports");
  assert.equal(buildEntryMessage("Fixed reports", "https://example.test/ticket/1"), "Fixed reports [ref: https://example.test/ticket/1]");
});

await runTest("renderer rejects empty add form", async () => {
  const { calls, renderer } = makeRenderer();
  renderer.elements.entryInput.value = "   ";

  await renderer.addEntry({ preventDefault() {} });

  assert.deepEqual(calls, []);
  assert.equal(renderer.elements.status.textContent, "Enter a log message.");
  assert.equal(renderer.elements.status.dataset.tone, "error");
  assert.equal(renderer.elements.entryInput.focusCount, 1);
});

await runTest("renderer rejects multiline references", async () => {
  const { calls, renderer } = makeRenderer();
  renderer.elements.entryInput.value = "Updated docs";
  renderer.elements.referenceInput.value = "CGI-123\nCGI-124";

  await renderer.addEntry({ preventDefault() {} });

  assert.deepEqual(calls, []);
  assert.equal(renderer.elements.status.textContent, "Ticket or link must be a single line.");
  assert.equal(renderer.elements.status.dataset.tone, "error");
  assert.equal(renderer.elements.referenceInput.focusCount, 1);
});

await runTest("renderer saves weekly editor text", async () => {
  const { calls, renderer } = makeRenderer();
  renderer.elements.weekEditor.value = "2026-04-30 saved\n";

  await renderer.saveWeek();

  assert.deepEqual(calls, [["saveWeek", "2026-04-30 saved\n"]]);
  assert.equal(renderer.elements.status.textContent, "Weekly file saved.");
  assert.equal(renderer.elements.status.dataset.tone, "ok");
  assert.equal(renderer.getCurrentView(), "week");
});

await runTest("renderer exports week formats", async () => {
  const { calls, document, renderer } = makeRenderer();

  await renderer.start();
  await document.exportButtons[1].listeners.click();

  assert.deepEqual(calls, [["getState"], ["exportWeek", "csv"]]);
  assert.equal(renderer.elements.status.textContent, "Exported CSV week to /tmp/tart/week.csv.");
  assert.equal(renderer.elements.status.dataset.tone, "ok");
});

await runTest("renderer handles canceled exports", async () => {
  const { calls, renderer } = makeRenderer({
    exportWeek: async (format) => {
      calls.push(["exportWeek", format]);
      return { canceled: true, format };
    },
  });

  await renderer.exportWeek("pdf");

  assert.deepEqual(calls, [["exportWeek", "pdf"]]);
  assert.equal(renderer.elements.status.textContent, "");
});

await runTest("renderer surfaces API errors", async () => {
  const { renderer } = makeRenderer({
    getState: async () => {
      throw new Error("disk unavailable");
    },
  });

  await renderer.loadState();

  assert.equal(renderer.elements.status.textContent, "disk unavailable");
  assert.equal(renderer.elements.status.dataset.tone, "error");
  assert.equal(renderer.elements.entryInput.disabled, false);
});

await runTest("renderer opens log directory through API", async () => {
  const { calls, renderer } = makeRenderer();

  await renderer.openLogDir();

  assert.deepEqual(calls, [["openLogDir"]]);
});

process.stdout.write(`\n${passCount} renderer tests passed, ${failCount} failed\n`);

if (failCount > 0) {
  process.exitCode = 1;
}
