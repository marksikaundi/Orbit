"use strict";

const vscode = require("vscode");
const { spawn } = require("child_process");
const fs = require("fs");
const path = require("path");

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("orbit.open", (uri) => {
      openOrbit(uri);
    }),
    vscode.commands.registerCommand("orbit.openWorkspace", () => {
      const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
      if (!folder) {
        vscode.window.showErrorMessage("Orbit: no workspace folder is open");
        return;
      }
      openOrbit(folder.uri);
    })
  );
}

function openOrbit(uri) {
  const folder = resolveFolder(uri);
  if (!folder) {
    vscode.window.showErrorMessage("Orbit: no folder to open");
    return;
  }
  const configured = vscode.workspace.getConfiguration("orbit").get("path") || "";
  try {
    launch(String(configured), folder);
  } catch (err) {
    const msg = err && err.message ? err.message : String(err);
    vscode.window.showErrorMessage("Orbit: failed to launch (" + msg + ")");
  }
}

function resolveFolder(uri) {
  if (uri && uri.fsPath) {
    try {
      if (fs.statSync(uri.fsPath).isDirectory()) return uri.fsPath;
    } catch {
      return path.dirname(uri.fsPath);
    }
    return path.dirname(uri.fsPath);
  }
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : null;
}

function launch(configured, folder) {
  if (process.platform === "darwin" && !configured) {
    spawn("open", ["-na", "Orbit.app", "--args", "--working-directory=" + folder], {
      detached: true,
      stdio: "ignore",
    }).unref();
    return;
  }
  const exe = configured || (process.platform === "win32" ? "orbit.exe" : "orbit");
  spawn(exe, ["--working-directory=" + folder], {
    detached: true,
    stdio: "ignore",
    shell: process.platform === "win32",
  }).unref();
}

function deactivate() {}

module.exports = { activate, deactivate };
