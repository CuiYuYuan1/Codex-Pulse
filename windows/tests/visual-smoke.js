const { app, BrowserWindow, ipcMain, screen } = require("electron");
const fs = require("fs");
const path = require("path");

const outputDirectory = path.resolve(__dirname, "../../output/windows-visual");
const fixtures = ["off", "off-large", "clear", "zero", "actual", "large-token", "almost-full", "full", "rain", "snow", "night", "api-rain", "api-126k"];
const captureWindows = [];
const collapsedWidths = new Map();

app.commandLine.appendSwitch("force-device-scale-factor", "2");
app.commandLine.appendSwitch("disable-gpu-shader-disk-cache");

function wait(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

ipcMain.handle("visual:resize", (event, mode) => {
  const window = BrowserWindow.fromWebContents(event.sender);
  if (!window || window.isDestroyed()) return null;
  const adaptiveRequest = mode && typeof mode === "object";
  const resolvedMode = adaptiveRequest ? mode.mode : mode;
  if (adaptiveRequest && resolvedMode === "collapsed" && Number.isFinite(Number(mode.width))) {
    window.visualCollapsedWidth = Math.max(283, Math.min(471, Math.round(Number(mode.width))));
    window.visualInformationEnabled = mode.informationEnabled === true;
  }
  const target = resolvedMode === "mini"
      ? { width: 88, height: 88 }
      : { width: 390, height: 810 };
  const old = window.getBounds();
  const area = screen.getDisplayMatching(old).workArea;
  const usesLeftEdgeAnchor = adaptiveRequest && resolvedMode === "collapsed";
  const usesRightEdgeAnchor = !usesLeftEdgeAnchor && (resolvedMode === "mini" || old.width <= 100);
  const preferredX = usesLeftEdgeAnchor
    ? old.x
    : usesRightEdgeAnchor
    ? old.x + old.width - target.width
    : Math.round(old.x + old.width / 2 - target.width / 2);
  const x = Math.min(area.x + area.width - target.width, Math.max(area.x, preferredX));
  const y = old.y;
  window.setBounds({ x, y, ...target }, false);
  return window.getBounds();
});

ipcMain.handle("visual:set-shape", (event, rects) => {
  const window = BrowserWindow.fromWebContents(event.sender);
  if (!window || window.isDestroyed()) return false;
  window.visualShape = Array.isArray(rects) ? rects : [];
  return true;
});

async function captureFixture(fixture, expanded = false, theme = "classic", outputName = fixture) {
  const informationDisabled = fixture.startsWith("off");
  const window = new BrowserWindow({
    width: 390,
    height: 810,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: [`--fixture=${fixture}`]
    }
  });
  window.visualInformationEnabled = !informationDisabled;
  captureWindows.push(window);

  window.webContents.on("did-fail-load", (_event, code, description, validatedURL) => {
    process.stderr.write(`did-fail-load ${code} ${description} ${validatedURL}\n`);
  });
  window.webContents.on("render-process-gone", (_event, details) => {
    process.stderr.write(`render-process-gone ${JSON.stringify(details)}\n`);
  });

  const pagePath = path.resolve(__dirname, "../src/renderer/index.html");
  process.stdout.write(`loading ${fixture}: ${pagePath}\n`);
  await window.loadFile(pagePath);
  await wait(500);
  await window.webContents.executeJavaScript(`
    document.querySelector('#themeStyleMenu [data-value="${theme}"]').click();
    document.querySelector('#activityBandStyleMenu [data-value="classic"]').click();
  `, true);
  await wait(120);
  if (!informationDisabled) {
    const layout = await window.webContents.executeJavaScript(`(() => {
      const stage = document.querySelector('.stage');
      const capsule = document.getElementById('capsule').getBoundingClientRect();
      const capsuleStyle = getComputedStyle(document.getElementById('capsule'));
      const stageStyle = getComputedStyle(stage);
      const token = document.querySelector('.token-readout').getBoundingClientRect();
      const bean = document.querySelector('.coffee-bean').getBoundingClientRect();
      const value = document.getElementById('todayTokens').getBoundingClientRect();
      const chevron = document.getElementById('chevron').getBoundingClientRect();
      const quota = document.getElementById('quotaRing').getBoundingClientRect();
      const information = document.getElementById('informationStrip').getBoundingClientRect();
      const weatherScene = document.getElementById('weatherScene').getBoundingClientRect();
      const capsuleAfterStyle = getComputedStyle(document.getElementById('capsule'), '::after');
      const themeEdgeStyle = getComputedStyle(document.querySelector('.capsule-theme-edge'));
      return {
        operationGap: chevron.left - token.right,
        quotaDividerGap: document.querySelector('.divider').getBoundingClientRect().left - quota.right,
        dividerTokenGap: token.left - document.querySelector('.divider').getBoundingClientRect().right,
        chevronRightInset: capsule.right - chevron.right,
        beanGap: parseFloat(getComputedStyle(document.querySelector('.token-readout')).columnGap),
        chevronWidth: chevron.width,
        weatherQuotaGap: quota.left - capsule.left - parseFloat(capsuleStyle.paddingLeft) - 62,
        capsuleHeight: capsule.height,
        weatherFadeWidth: weatherScene.width,
        innerSurfaceInset: parseFloat(capsuleAfterStyle.left),
        capsuleSurfaceColor: capsuleStyle.backgroundColor,
        themeEdgePadding: parseFloat(themeEdgeStyle.paddingTop),
        themeEdgeBackground: themeEdgeStyle.backgroundImage,
        informationGap: information.top - capsule.bottom,
        informationCenterDelta: information.left + information.width / 2 - (capsule.left + capsule.width / 2),
        capsuleLeftGuard: capsule.left,
        capsuleRightGuard: window.innerWidth - capsule.right,
        naturalWidth: Number(document.getElementById('capsule').dataset.naturalWidth),
        expandedWidth: Number(document.getElementById('capsule').dataset.expandedWidth),
        expectedWindowWidth: Math.max(283, Math.ceil(capsule.width + parseFloat(stageStyle.paddingLeft) + parseFloat(stageStyle.paddingRight)))
      };
    })()`, true);
    const actualWindowWidth = window.getBounds().width;
    const actualWindowHeight = window.getBounds().height;
    const expectedEdgePadding = theme === "classic" || theme === "amethyst" ? 1.2 : 1;
    if (layout.operationGap < 8
        || Math.abs(layout.operationGap - layout.quotaDividerGap) > 0.5
        || Math.abs(layout.operationGap - layout.dividerTokenGap) > 0.5
        || Math.abs(layout.beanGap - 5) > 0.5
        || Math.abs(layout.chevronWidth - 9) > 0.5
        || Math.abs(layout.weatherQuotaGap - 14) > 0.5
        || Math.abs(layout.chevronRightInset - 14) > 0.5
        || layout.expandedWidth !== Math.max(275, Math.ceil(layout.naturalWidth))
        || Math.abs(layout.capsuleHeight - 64) > 0.25
        || Math.abs(layout.weatherFadeWidth - 156) > 0.25
        || Math.abs(layout.innerSurfaceInset) > 0.25
        || layout.capsuleSurfaceColor !== 'rgba(0, 0, 0, 0)'
        || Math.abs(layout.themeEdgePadding - expectedEdgePadding) > 0.1
        || layout.themeEdgeBackground === 'none'
        || Math.abs(layout.informationGap - 8) > 0.5
        || Math.abs(layout.informationCenterDelta) > 0.5
        || layout.capsuleLeftGuard < 21.5
        || layout.capsuleRightGuard < 21.5
        || actualWindowWidth !== 390
        || actualWindowHeight !== 810) {
      throw new Error(`capsule spacing drifted: ${JSON.stringify({ fixture, actualWindowWidth, actualWindowHeight, ...layout })}`);
    }
    if (!expanded && theme === "classic") collapsedWidths.set(fixture, layout.expectedWindowWidth);
  } else {
    const layout = await window.webContents.executeJavaScript(`(() => {
      const stage = document.querySelector('.stage');
      const stageStyle = getComputedStyle(stage);
      const capsule = document.getElementById('capsule').getBoundingClientRect();
      const chevron = document.getElementById('chevron').getBoundingClientRect();
      const status = document.getElementById('statusDot').getBoundingClientRect();
      const capsuleStyle = getComputedStyle(document.getElementById('capsule'));
      return {
        capsuleWidth: capsule.width,
        rightInset: capsule.right - chevron.right,
        contentGap: parseFloat(capsuleStyle.columnGap),
        chevronWidth: chevron.width,
        compactContentCenterDelta: (status.left + chevron.right) / 2 - (capsule.left + capsule.width / 2),
        expectedWindowWidth: Math.max(283, Math.ceil(
          capsule.width + parseFloat(stageStyle.paddingLeft) + parseFloat(stageStyle.paddingRight)
        ))
      };
    })()`, true);
    const actualWindowWidth = window.getBounds().width;
    const actualWindowHeight = window.getBounds().height;
    if (actualWindowWidth !== 390
        || actualWindowHeight !== 810
        || Math.abs(layout.contentGap - 10) > 0.5
        || Math.abs(layout.chevronWidth - 9) > 0.5
        || Math.abs(layout.compactContentCenterDelta) > 0.5) {
      throw new Error(`compact capsule did not fit content: ${JSON.stringify({ fixture, actualWindowWidth, actualWindowHeight, ...layout })}`);
    }
    if (!expanded && theme === "classic") collapsedWidths.set(fixture, layout.expectedWindowWidth);
  }
  const collapsedShape = window.visualShape || [];
  const expectedShapeCount = informationDisabled ? 1 : 2;
  if (!expanded && collapsedShape.length !== expectedShapeCount) {
    throw new Error(`collapsed interaction shape is incorrect: ${JSON.stringify({ fixture, collapsedShape })}`);
  }
  if (expanded) {
    await window.webContents.executeJavaScript(`
      document.getElementById("capsule").dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
      )
    `, true);
    await wait(400);
    const expandedLayout = await window.webContents.executeJavaScript(`(() => {
      const detail = document.getElementById('detail').getBoundingClientRect();
      const capsuleMaterial = getComputedStyle(document.getElementById('capsule'), '::after').backgroundImage;
      const detailMaterial = getComputedStyle(document.getElementById('detail')).backgroundImage;
      return { left: detail.left, top: detail.top, right: detail.right, bottom: detail.bottom, detailWidth: detail.width, capsuleMaterial, detailMaterial };
    })()`, true);
    if (Math.abs(expandedLayout.detailWidth - 340) > 0.5) {
      throw new Error(`expanded detail did not follow window width: ${JSON.stringify({
        fixture,
        windowWidth: window.getBounds().width,
        ...expandedLayout
      })}`);
    }
    if (expandedLayout.capsuleMaterial !== expandedLayout.detailMaterial) {
      throw new Error(`expanded detail does not share the capsule theme material: ${JSON.stringify({ theme, expandedLayout })}`);
    }
    const expandedShape = window.visualShape || [];
    const shape = expandedShape[0];
    if (expandedShape.length !== 1
        || !shape
        || shape.x > expandedLayout.left
        || shape.y > expandedLayout.top
        || shape.x + shape.width < expandedLayout.right
        || shape.y + shape.height < expandedLayout.bottom) {
      throw new Error(`expanded interaction shape does not cover details: ${JSON.stringify({ expandedShape, expandedLayout })}`);
    }
  }
  const image = await window.webContents.capturePage(expanded
    ? undefined
    : { x: 0, y: 0, width: 390, height: informationDisabled ? 115 : 135 });
  const suffix = expanded ? "expanded" : "collapsed";
  fs.writeFileSync(path.join(outputDirectory, `${outputName}-${suffix}@2x.png`), image.toPNG());

  if (!expanded && fixture === "actual") {
    await window.webContents.executeJavaScript(`(() => {
      const capsule = document.getElementById("capsule");
      capsule.style.setProperty("--glow-x", String(capsule.getBoundingClientRect().width * 0.56) + "px");
      capsule.style.setProperty("--glow-y", "0px");
      capsule.classList.add("hovering");
    })()`, true);
    await wait(220);
    const hoverStyle = await window.webContents.executeJavaScript(`(() => {
      const capsule = document.getElementById('capsule');
      const haloElement = document.querySelector('.capsule-hover-halo');
      const crestElement = document.querySelector('.capsule-hover-crest');
      const halo = getComputedStyle(haloElement);
      const angular = getComputedStyle(haloElement, '::before');
      const crest = getComputedStyle(crestElement);
      const crestOuter = getComputedStyle(crestElement, '::before');
      const core = getComputedStyle(capsule, '::before');
      return {
        opacity: Number(halo.opacity),
        filter: halo.filter,
        haloPadding: parseFloat(halo.paddingTop),
        haloScale: Number(halo.scale),
        angularPadding: parseFloat(angular.paddingTop),
        angularClip: angular.clipPath,
        crestWidth: parseFloat(crest.width),
        crestHeight: parseFloat(crest.height),
        crestOpacity: Number(crest.opacity),
        crestFilter: crestOuter.filter,
        crestBackground: crestOuter.backgroundImage,
        corePadding: parseFloat(core.paddingTop),
        detachedBloomPresent: Boolean(document.querySelector('.capsule-hover-bloom'))
      };
    })()`, true);
    if (Math.abs(hoverStyle.opacity - .72) > 0.01
        || !hoverStyle.filter.includes('blur(5.2px)')
        || Math.abs(hoverStyle.haloPadding - 4.4) > 0.1
        || Math.abs(hoverStyle.haloScale - 1.006) > 0.01
        || Math.abs(hoverStyle.angularPadding - 2.35) > 0.1
        || !hoverStyle.angularClip.includes('48px')
        || Math.abs(hoverStyle.crestWidth - 36) > 0.1
        || Math.abs(hoverStyle.crestHeight - 5) > 0.1
        || Math.abs(hoverStyle.crestOpacity - .82) > 0.01
        || hoverStyle.crestFilter !== 'none'
        || !hoverStyle.crestBackground.includes('radial-gradient')
        || Math.abs(hoverStyle.corePadding - 3.2) > 0.1
        || hoverStyle.detachedBloomPresent) {
      throw new Error(`hover halo escaped the rounded capsule edge: ${JSON.stringify(hoverStyle)}`);
    }
    const hoverImage = await window.webContents.capturePage({ x: 0, y: 0, width: 390, height: 115 });
    fs.writeFileSync(path.join(outputDirectory, "actual-hover@2x.png"), hoverImage.toPNG());

    await window.webContents.executeJavaScript(`(() => {
      const capsule = document.getElementById('capsule');
      capsule.style.setProperty('--glow-x', capsule.getBoundingClientRect().width + 'px');
      capsule.style.setProperty('--glow-y', '0px');
      capsule.dataset.glowEdge = 'top';
    })()`, true);
    await wait(180);
    const cornerHoverImage = await window.webContents.capturePage({ x: 0, y: 0, width: 390, height: 115 });
    fs.writeFileSync(path.join(outputDirectory, "actual-hover-corner@2x.png"), cornerHoverImage.toPNG());

    await window.webContents.executeJavaScript(`(() => {
      const capsule = document.getElementById('capsule');
      const marquee = document.querySelector('.capsule-activity-marquee');
      const band = document.querySelector('.activity-band');
      capsule.classList.remove('hovering');
      capsule.classList.add('task-active');
      for (const element of [marquee, band]) {
        element.style.setProperty('--activity-x', '50%');
        element.style.setProperty('--activity-y', '102%');
        element.style.setProperty('--activity-radius', '42px');
      }
      band.style.animation = 'none';
      band.style.opacity = '1';
    })()`, true);
    await wait(360);
    const activityStyle = await window.webContents.executeJavaScript(`(() => {
      const band = getComputedStyle(document.querySelector('.activity-band'));
      return { filter: band.filter, contain: band.contain, activityY: band.getPropertyValue('--activity-y').trim() };
    })()`, true);
    if (activityStyle.activityY !== '102%'
        || !activityStyle.filter.includes('2.5px 2.5px')
        || activityStyle.contain.includes('paint')) {
      throw new Error(`activity light did not expand outside the capsule: ${JSON.stringify(activityStyle)}`);
    }
    const activityImage = await window.webContents.capturePage({ x: 0, y: 0, width: 390, height: 115 });
    fs.writeFileSync(path.join(outputDirectory, "actual-activity-outward@2x.png"), activityImage.toPNG());
  }
  window.destroy();
}

async function captureMini(style, taskMode = null, activityStyle = null, theme = null) {
  const window = new BrowserWindow({
    width: 88,
    height: 88,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: [`--fixture=${style === "tokens" ? "large-token" : style === "quota" ? "almost-full" : "clear"}`]
    }
  });
  captureWindows.push(window);

  const pagePath = path.resolve(__dirname, "../src/renderer/index.html");
  process.stdout.write(`loading mini ${style}: ${pagePath}\n`);
  await window.loadFile(pagePath);
  await wait(250);
  await window.webContents.executeJavaScript(`
    document.querySelector('#miniStyleMenu [data-value="${style}"]').click();
    ${activityStyle ? `document.querySelector('#activityBandStyleMenu [data-value="${activityStyle}"]').click();` : ""}
    ${theme ? `document.querySelector('#themeStyleMenu [data-value="${theme}"]').click();` : ""}
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
    ${taskMode ? `document.getElementById("capsule").classList.add("task-active"${taskMode === "attention" ? `, "task-attention"` : ""});` : ""}
  `, true);
  await wait(650);
  const centers = await window.webContents.executeJavaScript(`(() => {
    const capsule = document.getElementById('miniCapsule').getBoundingClientRect();
    const ring = document.querySelector('.mini-ring-svg').getBoundingClientRect();
    return {
      dx: ring.left + ring.width / 2 - (capsule.left + capsule.width / 2),
      dy: ring.top + ring.height / 2 - (capsule.top + capsule.height / 2),
      oneCenter: [...document.querySelectorAll('.mini-ring-svg circle')]
        .every((circle) => circle.getAttribute('cx') === '34' && circle.getAttribute('cy') === '34')
    };
  })()`, true);
  if (Math.abs(centers.dx) > 0.25 || Math.abs(centers.dy) > 0.25 || !centers.oneCenter) {
    throw new Error(`mini ring is not centered: ${JSON.stringify({ style, ...centers })}`);
  }
  const image = await window.webContents.capturePage();
  const suffix = [theme, activityStyle, taskMode].filter(Boolean).map((value) => `-${value}`).join("");
  fs.writeFileSync(path.join(outputDirectory, `mini-${style}${suffix}@2x.png`), image.toPNG());

  if (style === "quota" && !taskMode) {
    window.webContents.sendInputEvent({ type: "mouseDown", x: 44, y: 44, button: "left", clickCount: 1 });
    window.webContents.sendInputEvent({ type: "mouseUp", x: 44, y: 44, button: "left", clickCount: 1 });
    await wait(850);
    const interaction = await window.webContents.executeJavaScript(`({
      isMini: document.documentElement.classList.contains("mini-mode"),
      isExpanded: document.getElementById("capsule").getAttribute("aria-expanded")
    })`, true);
    if (interaction.isMini || interaction.isExpanded !== "true") {
      throw new Error(`mini single click did not expand details: ${JSON.stringify(interaction)}`);
    }
  }
}

async function captureSettingsAndAssertMiniPicker() {
  const window = new BrowserWindow({
    width: 390,
    height: 810,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: ["--fixture=clear"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(250);
  const result = await window.webContents.executeJavaScript(`new Promise((resolve) => {
    document.getElementById("capsule").dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true })
    );
    setTimeout(() => {
      document.getElementById("moreSettingsToggle").click();
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const row = document.querySelector(".mini-style-preference-row");
        const updateRow = document.querySelector(".update-preference-row");
        const container = document.getElementById("appearanceSettings");
        const rowRect = row.getBoundingClientRect();
        const updateRect = updateRow.getBoundingClientRect();
        const containerRect = container.getBoundingClientRect();
        resolve({
          hidden: container.hidden,
          display: getComputedStyle(row).display,
          height: rowRect.height,
          inside: rowRect.top >= containerRect.top && rowRect.bottom <= containerRect.bottom,
          label: document.getElementById("miniStyleLabel").textContent,
          updateDisplay: getComputedStyle(updateRow).display,
          updateInside: updateRect.top >= containerRect.top && updateRect.bottom <= containerRect.bottom,
          updateVersion: document.getElementById("updateVersion").textContent
        });
      }));
    }, 280);
  })`, true);
  if (result.hidden || result.display === "none" || result.height < 28 || !result.inside || !result.label
      || result.updateDisplay === "none" || !result.updateInside || !result.updateVersion) {
    throw new Error(`mini settings picker is not visible: ${JSON.stringify(result)}`);
  }
  await wait(150);
  const image = await window.webContents.capturePage();
  fs.writeFileSync(path.join(outputDirectory, "clear-settings@2x.png"), image.toPNG());
}

async function assertPointerDoubleClickMinimizes() {
  const window = new BrowserWindow({
    width: 390,
    height: 810,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: ["--fixture=clear"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(250);
  const click = (clickCount, x = 195, y = 46) => {
    window.webContents.sendInputEvent({ type: "mouseDown", x, y, button: "left", clickCount });
    window.webContents.sendInputEvent({ type: "mouseUp", x, y, button: "left", clickCount });
  };
  click(1);
  await wait(120);
  click(2);
  await wait(140);
  const activeMiniTransition = await window.webContents.executeJavaScript(`(() => ({
    transitioning: document.documentElement.classList.contains("mini-transitioning"),
    capsuleAnimations: document.getAnimations().filter((animation) => {
      const target = animation.effect?.target;
      return target?.id === "capsule";
    }).length
  }))()`, true);
  if (!activeMiniTransition.transitioning || activeMiniTransition.capsuleAnimations < 1) {
    throw new Error(`mini transition did not animate as rigid capsules: ${JSON.stringify(activeMiniTransition)}`);
  }
  const transitionImage = await window.webContents.capturePage();
  fs.writeFileSync(path.join(outputDirectory, "mini-transition-mid@2x.png"), transitionImage.toPNG());
  await wait(560);
  const isMini = await window.webContents.executeJavaScript(
    `document.documentElement.classList.contains("mini-mode")`,
    true
  );
  if (!isMini) throw new Error("real pointer double click did not enable mini mode");
  const bounds = window.getBounds();
  if (bounds.width !== 88 || bounds.height !== 88) {
    throw new Error(`mini window did not finish resizing: ${JSON.stringify(bounds)}`);
  }
  const miniLayout = await window.webContents.executeJavaScript(`(() => {
    const capsule = document.getElementById("capsule").getBoundingClientRect();
    const mini = document.getElementById("miniCapsule").getBoundingClientRect();
    return {
      capsule: { left: capsule.left, top: capsule.top, width: capsule.width, height: capsule.height },
      mini: { left: mini.left, top: mini.top, width: mini.width, height: mini.height },
      viewport: { width: innerWidth, height: innerHeight }
    };
  })()`, true);
  const visible = miniLayout.mini.left >= 0
    && miniLayout.mini.top >= 0
    && miniLayout.mini.left + miniLayout.mini.width <= miniLayout.viewport.width
    && miniLayout.mini.top + miniLayout.mini.height <= miniLayout.viewport.height;
  if (Math.abs(miniLayout.capsule.width - 68) > 0.5
      || Math.abs(miniLayout.capsule.height - 68) > 0.5
      || Math.abs(miniLayout.capsule.left - 10) > 0.5
      || Math.abs(miniLayout.capsule.top - 10) > 0.5
      || !visible) {
    throw new Error(`mini capsule is clipped or outside the window: ${JSON.stringify(miniLayout)}`);
  }
  window.webContents.send("pulse:collapse");
  await wait(420);
  const afterDesktopBlur = await window.webContents.executeJavaScript(`({
    isMini: document.documentElement.classList.contains("mini-mode"),
    capsuleWidth: document.getElementById("capsule").getBoundingClientRect().width
  })`, true);
  const afterBlurBounds = window.getBounds();
  if (!afterDesktopBlur.isMini
      || Math.abs(afterDesktopBlur.capsuleWidth - 68) > 0.5
      || afterBlurBounds.width !== 88
      || afterBlurBounds.height !== 88) {
    throw new Error(`desktop blur restored the full capsule: ${JSON.stringify({ afterDesktopBlur, afterBlurBounds })}`);
  }

  // Match the macOS event contract: a second double-click restores the full
  // collapsed capsule, while a single click from mini restores and opens the
  // detail card. Neither path may leave a pending single-click behind.
  click(2, 44, 44);
  await wait(720);
  const restored = await window.webContents.executeJavaScript(`({
    isMini: document.documentElement.classList.contains('mini-mode'),
    expanded: document.getElementById('capsule').getAttribute('aria-expanded'),
    width: document.getElementById('capsule').getBoundingClientRect().width,
    height: document.getElementById('capsule').getBoundingClientRect().height
  })`, true);
  const restoredBounds = window.getBounds();
  if (restored.isMini
      || restored.expanded !== 'false'
      || Math.abs(restored.width - 275) > 0.5
      || Math.abs(restored.height - 64) > 0.5
      || restoredBounds.width !== 390
      || restoredBounds.height !== 810) {
    throw new Error(`double click did not smoothly restore the collapsed capsule: ${JSON.stringify({ restored, restoredBounds })}`);
  }

  click(2, 195, 46);
  await wait(520);
  const minimizedAgain = await window.webContents.executeJavaScript(
    `document.documentElement.classList.contains('mini-mode')`,
    true
  );
  if (!minimizedAgain) throw new Error('second double click cycle did not return to mini mode');
  click(1, 44, 44);
  await wait(980);
  const expandedFromMini = await window.webContents.executeJavaScript(`({
    isMini: document.documentElement.classList.contains('mini-mode'),
    expanded: document.getElementById('capsule').getAttribute('aria-expanded'),
    detailOpen: document.getElementById('detail').classList.contains('open'),
    informationVisible: getComputedStyle(document.getElementById('informationStrip')).display !== 'none'
  })`, true);
  if (expandedFromMini.isMini
      || expandedFromMini.expanded !== 'true'
      || !expandedFromMini.detailOpen
      || expandedFromMini.informationVisible) {
    throw new Error(`single click from mini did not open details like macOS: ${JSON.stringify(expandedFromMini)}`);
  }
}

async function assertMagnetAndDetailStayStable(fixture = "clear") {
  const informationDisabled = fixture.startsWith("off");
  const window = new BrowserWindow({
    width: 390,
    height: 810,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    webPreferences: {
      preload: path.join(__dirname, "visual-preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      additionalArguments: [`--fixture=${fixture}`]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(700);
  const base = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("capsule").getBoundingClientRect();
    const surface = document.querySelector(".capsule-theme-edge").getBoundingClientRect();
    const token = document.getElementById("todayTokens").getBoundingClientRect();
    return {
      left: rect.left, top: rect.top, width: rect.width, height: rect.height,
      surfaceLeft: surface.left, surfaceTop: surface.top,
      tokenLeft: token.left, tokenTop: token.top
    };
  })()`, true);
  const hoverX = Math.round(base.left + base.width - 8);
  const hoverY = Math.round(base.top + base.height / 2);
  window.webContents.sendInputEvent({ type: "mouseMove", x: hoverX, y: hoverY });
  await wait(450);
  const attracted = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("capsule").getBoundingClientRect();
    const surface = document.querySelector(".capsule-theme-edge").getBoundingClientRect();
    const token = document.getElementById("todayTokens").getBoundingClientRect();
    return {
      capsuleDx: rect.left - ${base.left}, capsuleDy: rect.top - ${base.top},
      surfaceDx: surface.left - ${base.surfaceLeft}, surfaceDy: surface.top - ${base.surfaceTop},
      tokenDx: token.left - ${base.tokenLeft}, tokenDy: token.top - ${base.tokenTop}
    };
  })()`, true);
  const attraction = Math.hypot(attracted.capsuleDx, attracted.capsuleDy);
  const rigidBodyDrift = Math.hypot(
    attracted.tokenDx - attracted.capsuleDx,
    attracted.tokenDy - attracted.capsuleDy
  );
  const surfaceDrift = Math.hypot(
    attracted.surfaceDx - attracted.capsuleDx,
    attracted.surfaceDy - attracted.capsuleDy
  );
  if (attraction < 6 || attraction > 12 || rigidBodyDrift > 0.25 || surfaceDrift > 0.25) {
    throw new Error(`capsule magnet is not active or exceeds safe travel: ${JSON.stringify({ attraction, ...attracted })}`);
  }
  window.webContents.sendInputEvent({ type: "mouseMove", x: 2, y: 2 });
  await wait(600);
  const settled = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("capsule").getBoundingClientRect();
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  })()`, true);
  if (Math.abs(settled.left - base.left) > 0.5 || Math.abs(settled.top - base.top) > 0.5) {
    throw new Error(`capsule magnet did not return to center: ${JSON.stringify({ base, settled })}`);
  }
  const samplesPromise = window.webContents.executeJavaScript(`new Promise((resolve) => {
    const samples = [];
    const startedAt = performance.now();
    const sample = () => {
      const rect = document.getElementById("capsule").getBoundingClientRect();
      samples.push({
        time: performance.now() - startedAt,
        left: window.screenX + rect.left,
        top: window.screenY + rect.top,
        height: rect.height,
        opacity: Number(getComputedStyle(document.getElementById("detail")).opacity)
      });
      if (performance.now() - startedAt < 920) requestAnimationFrame(sample);
      else resolve(samples);
    };
    requestAnimationFrame(sample);
  })`, true);
  const clickX = Math.round(settled.left + settled.width / 2);
  const clickY = Math.round(settled.top + settled.height / 2);
  window.webContents.sendInputEvent({ type: "mouseDown", x: clickX, y: clickY, button: "left", clickCount: 1 });
  window.webContents.sendInputEvent({ type: "mouseUp", x: clickX, y: clickY, button: "left", clickCount: 1 });
  const samples = await samplesPromise;
  const lefts = samples.map((sample) => sample.left);
  const tops = samples.map((sample) => sample.top);
  const horizontalDrift = Math.max(...lefts) - Math.min(...lefts);
  const verticalDrift = Math.max(...tops) - Math.min(...tops);
  const expanded = await window.webContents.executeJavaScript(
    `document.getElementById("capsule").getAttribute("aria-expanded")`,
    true
  );
  const expansionOpacities = samples.map((sample) => sample.opacity);
  const expansionIntervals = samples.slice(1).map((sample, index) => sample.time - samples[index].time).sort((a, b) => a - b);
  const expansionP95 = expansionIntervals[Math.floor(expansionIntervals.length * .95)] || Infinity;
  const expansionReversed = expansionOpacities.some((value, index) => index > 0
    && value + 0.025 < expansionOpacities[index - 1]);
  if (horizontalDrift > 0.75
      || verticalDrift > 0.75
      || expansionReversed
      || expansionP95 > 34
      || samples.length < 35
      || expanded !== "true") {
    throw new Error(`detail expansion moved or dropped frames: ${JSON.stringify({ attraction, horizontalDrift, verticalDrift, expansionP95, frameCount: samples.length, expanded })}`);
  }

  const collapseSamplesPromise = window.webContents.executeJavaScript(`new Promise((resolve) => {
    const samples = [];
    const startedAt = performance.now();
    const sample = () => {
      const rect = document.getElementById("capsule").getBoundingClientRect();
      samples.push({
        time: performance.now() - startedAt,
        left: window.screenX + rect.left,
        top: window.screenY + rect.top,
        opacity: Number(getComputedStyle(document.getElementById("detail")).opacity)
      });
      if (performance.now() - startedAt < 980) requestAnimationFrame(sample);
      else resolve(samples);
    };
    requestAnimationFrame(sample);
  })`, true);
  const expandedRect = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("capsule").getBoundingClientRect();
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  })()`, true);
  const collapseX = Math.round(expandedRect.left + expandedRect.width / 2);
  const collapseY = Math.round(expandedRect.top + expandedRect.height / 2);
  window.webContents.sendInputEvent({ type: "mouseDown", x: collapseX, y: collapseY, button: "left", clickCount: 1 });
  window.webContents.sendInputEvent({ type: "mouseUp", x: collapseX, y: collapseY, button: "left", clickCount: 1 });
  const collapseSamples = await collapseSamplesPromise;
  const collapseLefts = collapseSamples.map((sample) => sample.left);
  const collapseTops = collapseSamples.map((sample) => sample.top);
  const collapseOpacities = collapseSamples.map((sample) => sample.opacity);
  const collapseIntervals = collapseSamples.slice(1).map((sample, index) => sample.time - collapseSamples[index].time).sort((a, b) => a - b);
  const collapseP95 = collapseIntervals[Math.floor(collapseIntervals.length * .95)] || Infinity;
  const collapseHorizontalDrift = Math.max(...collapseLefts) - Math.min(...collapseLefts);
  const collapseVerticalDrift = Math.max(...collapseTops) - Math.min(...collapseTops);
  const collapseReversed = collapseOpacities.some((value, index) => index > 0
    && value > collapseOpacities[index - 1] + 0.025);
  const collapsedState = await window.webContents.executeJavaScript(
    `document.getElementById("capsule").getAttribute("aria-expanded")`,
    true
  );
  const collapsedBounds = window.getBounds();
  if (collapseHorizontalDrift > 0.75
      || collapseVerticalDrift > 0.75
      || collapseReversed
      || collapseP95 > 34
      || collapseSamples.length < 35
      || collapsedState !== "false"
      || collapsedBounds.width !== 390
      || collapsedBounds.height !== 810) {
    throw new Error(`detail collapse flashed or moved capsule: ${JSON.stringify({
      fixture,
      collapseHorizontalDrift,
      collapseVerticalDrift,
      collapseP95,
      frameCount: collapseSamples.length,
      collapseReversed,
      collapsedState,
      collapsedBounds
    })}`);
  }
}

app.whenReady().then(async () => {
  fs.mkdirSync(outputDirectory, { recursive: true });
  // Keep one inert window alive while individual fixture windows are
  // destroyed, otherwise macOS Electron may tear down the renderer host in
  // the gap before the next fixture starts loading.
  const keeperWindow = new BrowserWindow({ width: 1, height: 1, show: false });
  captureWindows.push(keeperWindow);
  for (const fixture of fixtures) await captureFixture(fixture);
  if ((collapsedWidths.get("large-token") || 0) < (collapsedWidths.get("zero") || 0)) {
    throw new Error(`Token width made the information capsule shrink: ${JSON.stringify(Object.fromEntries(collapsedWidths))}`);
  }
  if ((collapsedWidths.get("off-large") || 0) < (collapsedWidths.get("off") || 0)) {
    throw new Error(`Token width made the compact capsule shrink: ${JSON.stringify(Object.fromEntries(collapsedWidths))}`);
  }
  await captureFixture("rain", true);
  for (const theme of ["classic", "midnight", "graphite", "forest", "amethyst"]) {
    await captureFixture("clear", false, theme, `theme-${theme}`);
    await captureFixture("clear", true, theme, `theme-${theme}`);
  }
  await captureSettingsAndAssertMiniPicker();
  await assertPointerDoubleClickMinimizes();
  await assertMagnetAndDetailStayStable("clear");
  await assertMagnetAndDetailStayStable("off");
  for (const style of ["quota", "tokens", "status", "weather", "time"]) {
    await captureMini(style);
  }
  await captureMini("quota", "working");
  await captureMini("quota", "attention");
  await captureMini("quota", "working", "classic", "classic");
  await captureMini("quota", "working", "aurora", "midnight");
  await captureMini("quota", "working", "mono", "graphite");
  await captureMini("quota", "attention", "lava", "forest");
  await captureMini("quota", "attention", "neon", "amethyst");
  captureWindows.forEach((window) => { if (!window.isDestroyed()) window.destroy(); });
  app.quit();
}).catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
  app.exit(1);
});
