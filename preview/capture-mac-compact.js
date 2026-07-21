const { app, BrowserWindow } = require("electron");
const fs = require("fs");
const path = require("path");

app.commandLine.appendSwitch("force-device-scale-factor", "2");

app.whenReady().then(async () => {
  const window = new BrowserWindow({
    width: 324,
    height: 116,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000"
  });
  await window.loadFile(path.join(__dirname, "mac-compact-capsule.html"));
  await new Promise((resolve) => setTimeout(resolve, 500));
  const image = await window.webContents.capturePage();
  const output = path.resolve(__dirname, "../output/mac-compact-preview@2x.png");
  fs.writeFileSync(output, image.toPNG());
  window.destroy();
  app.quit();
}).catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  app.exit(1);
});
