# TART

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
~/Documents/tart
```

## What To Customize First

1. Replace the icon files in `assets/`.
2. Update the copy in `desktop/index.html`.
3. Replace `desktop/app-core.cjs` if your project needs a different storage model.
4. Adjust export behavior in `desktop/main.cjs`.

## Notes

The scaffold intentionally keeps the file-backed weekly log model from tart so you can start from a working desktop app instead of an empty Electron shell.
