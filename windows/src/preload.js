const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("pulse", {
  getState: () => ipcRenderer.invoke("pulse:get-state"),
  refresh: () => ipcRenderer.invoke("pulse:refresh"),
  checkForUpdates: () => ipcRenderer.invoke("pulse:check-update"),
  notifyNetworkOnline: () => ipcRenderer.send("pulse:network-online"),
  performUpdate: () => ipcRenderer.invoke("pulse:perform-update"),
  skipUpdate: (version) => ipcRenderer.invoke("pulse:skip-update", String(version || "")),
  chooseCodex: () => ipcRenderer.invoke("pulse:choose-codex"),
  clearCodexPath: () => ipcRenderer.invoke("pulse:clear-codex-path"),
  searchLocations: (query) => ipcRenderer.invoke("pulse:search-locations", String(query || "")),
  setInformationBarEnabled: (enabled) => ipcRenderer.invoke("pulse:set-information-enabled", Boolean(enabled)),
  setInformationBarLocation: (location) => ipcRenderer.invoke("pulse:set-information-location", location),
  openExternal: (url) => ipcRenderer.invoke("pulse:open-external", String(url || "")),
  setWindowShape: (rects) => ipcRenderer.invoke(
    "pulse:set-window-shape",
    Array.isArray(rects) ? rects.map((rect) => ({
      x: Number(rect?.x),
      y: Number(rect?.y),
      width: Number(rect?.width),
      height: Number(rect?.height)
    })) : []
  ),
  resize: (mode) => {
    if (mode && typeof mode === "object") {
      return ipcRenderer.invoke("pulse:resize", {
        mode: String(mode.mode || "collapsed"),
        width: Number(mode.width),
        informationEnabled: mode.informationEnabled === true
      });
    }
    return ipcRenderer.invoke(
      "pulse:resize",
      typeof mode === "string" ? mode : Boolean(mode)
    );
  },
  beginDrag: (x, y) => ipcRenderer.send("pulse:drag-begin", { x, y }),
  dragTo: (x, y) => ipcRenderer.send("pulse:drag-move", { x, y }),
  endDrag: () => ipcRenderer.send("pulse:drag-end"),
  quit: () => ipcRenderer.send("pulse:quit"),
  onState: (callback) => {
    const listener = (_event, state) => callback(state);
    ipcRenderer.on("pulse:state", listener);
    return () => ipcRenderer.removeListener("pulse:state", listener);
  },
  onCollapse: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("pulse:collapse", listener);
    return () => ipcRenderer.removeListener("pulse:collapse", listener);
  },
  onExpand: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("pulse:expand", listener);
    return () => ipcRenderer.removeListener("pulse:expand", listener);
  }
});
