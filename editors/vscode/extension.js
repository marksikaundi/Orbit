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
  try {
    if (/[\0\r\n]/.test(folder)) {
      throw new Error("invalid folder path");
    }
    launch(userOrbitPath(), folder);
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

// User-scoped `orbit.path` only. Workspace/folder values are ignored so a
// cloned repo cannot redirect Open in Orbit Terminal to an attacker binary.
function userOrbitPath() {
  const inspected = vscode.workspace.getConfiguration("orbit").inspect("path");
  if (!inspected) return "";
  if (inspected.workspaceValue || inspected.workspaceFolderValue) {
    vscode.window.showWarningMessage(
      "Orbit ignored workspace orbit.path. Set it in User settings instead."
    );
  }
  const fromUser = inspected.globalValue;
  return typeof fromUser === "string" ? fromUser : "";
}

function resolveExecutable(configured) {
  const trimmed = String(configured || "").trim();
  if (!trimmed) {
    return process.platform === "win32" ? "orbit.exe" : "orbit";
  }
  if (/[\0\r\n]/.test(trimmed)) {
    throw new Error("orbit.path contains invalid characters");
  }
  if (process.platform === "win32" && /[&|<>^"]/.test(trimmed)) {
    throw new Error("orbit.path must be a single executable path");
  }
  if (!/[\\/]/.test(trimmed)) {
    return trimmed;
  }
  if (!path.isAbsolute(trimmed)) {
    throw new Error("orbit.path must be an absolute path or a command name on PATH");
  }
  let st;
  try {
    st = fs.statSync(trimmed);
  } catch {
    throw new Error("orbit.path does not exist: " + trimmed);
  }
  if (!st.isFile()) {
    throw new Error("orbit.path is not a file");
  }
  return trimmed;
}

function launch(configured, folder) {
  if (process.platform === "darwin" && !configured) {
    spawnDetached("open", ["-na", "Orbit.app", "--args", "--working-directory", folder]);
    return;
  }
  const exe = resolveExecutable(configured);
  spawnDetached(exe, ["--working-directory", folder]);
}

function spawnDetached(exe, argv) {
  const child = spawn(exe, argv, {
    detached: true,
    stdio: "ignore",
    shell: false,
    windowsHide: true,
  });
  child.on("error", (err) => {
    const msg = err && err.message ? err.message : String(err);
    vscode.window.showErrorMessage("Orbit: failed to launch (" + msg + ")");
  });
  child.unref();
}

function deactivate() {}

module.exports = { activate, deactivate };
