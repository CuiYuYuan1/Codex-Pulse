const { contextBridge, ipcRenderer, webUtils } = require("electron");

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
        informationEnabled: mode.informationEnabled === true,
        petScale: Number(mode.petScale),
        petCharacter: String(mode.petCharacter || ""),
        conversationExpanded: mode.conversationExpanded === true
      });
    }
    return ipcRenderer.invoke(
      "pulse:resize",
      typeof mode === "string" ? mode : Boolean(mode)
    );
  },
  beginDrag: (x, y) => ipcRenderer.send("pulse:drag-begin", { x, y }),
  dragTo: (x, y) => ipcRenderer.send("pulse:drag-move", { x, y }),
  endDrag: (x, y, moved = false) => ipcRenderer.send("pulse:drag-end", {
    x: Number(x),
    y: Number(y),
    moved: moved === true
  }),
  planPetRoam: (options) => ipcRenderer.invoke("pulse:pet-roam-plan", {
    forceInteraction: options?.forceInteraction === true
  }),
  runPetRoam: (plan) => ipcRenderer.invoke("pulse:pet-roam-run", {
    x: Number(plan?.x),
    y: Number(plan?.y),
    duration: Number(plan?.duration),
    arcHeight: Number(plan?.arcHeight)
  }),
  cancelPetRoam: () => ipcRenderer.send("pulse:pet-roam-cancel"),
  setBlackHoleCaptureMode: (enabled) => ipcRenderer.invoke(
    "pulse:set-black-hole-capture-mode",
    enabled === true
  ),
  getBlackHoleCaptureGeometry: () => ipcRenderer.invoke(
    "pulse:get-black-hole-capture-geometry"
  ),
  trashBlackHoleFiles: (files) => {
    const paths = Array.from(files || [], (file) => webUtils.getPathForFile(file))
      .filter(Boolean);
    return ipcRenderer.invoke("pulse:black-hole-trash-files", paths);
  },
  showPetSwitchMenu: (current) => ipcRenderer.invoke(
    "pulse:show-pet-switch-menu",
    String(current || "")
  ),
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
  },
  onPetDrop: (callback) => {
    const listener = (_event, drop) => callback(drop);
    ipcRenderer.on("pulse:pet-drop", listener);
    return () => ipcRenderer.removeListener("pulse:pet-drop", listener);
  },
  onBlackHoleCaptureGeometry: (callback) => {
    const listener = (_event, geometry) => callback(geometry);
    ipcRenderer.on("pulse:black-hole-capture-geometry", listener);
    return () => ipcRenderer.removeListener("pulse:black-hole-capture-geometry", listener);
  },
  onSystemResume: (callback) => {
    const listener = () => callback();
    ipcRenderer.on("pulse:system-resume", listener);
    return () => ipcRenderer.removeListener("pulse:system-resume", listener);
  }
});
