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
  window.visualResizeRequest = mode;
  const adaptiveRequest = mode && typeof mode === "object";
  const resolvedMode = adaptiveRequest ? mode.mode : mode;
  if (adaptiveRequest && resolvedMode === "collapsed" && Number.isFinite(Number(mode.width))) {
    window.visualCollapsedWidth = Math.max(283, Math.min(471, Math.round(Number(mode.width))));
    window.visualInformationEnabled = mode.informationEnabled === true;
  }
  // Most visual fixtures retain a stable canvas so their screenshots remain
  // directly comparable. Individual tests still inspect the exact adaptive
  // resize request that production receives.
  const target = { width: 390, height: 810 };
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

async function captureMini(style, taskMode = null, activityStyle = null, theme = null, pet = "dino") {
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
    document.querySelector('#petCharacterMenu [data-value="${pet}"]').click();
    ${activityStyle ? `document.querySelector('#activityBandStyleMenu [data-value="${activityStyle}"]').click();` : ""}
    ${theme ? `document.querySelector('#themeStyleMenu [data-value="${theme}"]').click();` : ""}
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
    ${taskMode ? `render({ ...currentState, task: { state: "${taskMode}", label: "${taskMode === "attention" ? "等待授权" : "思考中"}", startedAt: Date.now() } });` : ""}
  `, true);
  if (pet === "fox" && taskMode === "working" && !activityStyle && !theme) {
    await wait(220);
    const bridgeImage = await window.webContents.capturePage();
    fs.writeFileSync(
      path.join(outputDirectory, "mini-fox-idle-to-working-bridge@2x.png"),
      bridgeImage.toPNG()
    );
    await wait(430);
  } else {
    await wait(650);
  }
  const expectedDisplayFrames = {
    dino: [126, 23, 76, 34],
    cat: [123, 17, 81, 36],
    bunny: [122, 21, 82, 34],
    ghost: [125, 17, 79, 36],
    robot: [122, 21, 82, 34],
    fox: [124, 19, 80, 34]
  };
  const [displayX, displayY, displayWidth, displayHeight] = expectedDisplayFrames[pet];
  const petLayout = await window.webContents.executeJavaScript(`(() => {
    const capsule = document.getElementById('miniCapsule').getBoundingClientRect();
    const animations = [
      document.getElementById('petAnimation'),
      document.getElementById('petAnimationNext')
    ];
    const rasterAnimation = animations.find((candidate) =>
      candidate.getAttribute('src') && Number.parseFloat(getComputedStyle(candidate).opacity) > .5
    ) || animations.find((candidate) => candidate.getAttribute('src')) || animations[0];
    const catCanvas = document.getElementById('petCatCanvas');
    const animation = catCanvas;
    const image = animation.getBoundingClientRect();
    const value = document.getElementById('miniValue').getBoundingClientRect();
    return {
      width: capsule.width,
      height: capsule.height,
      imageDX: image.left - capsule.left,
      imageDY: image.top - capsule.top,
      imageWidth: image.width,
      imageHeight: image.height,
      naturalWidth: animation.naturalWidth || animation.width,
      naturalHeight: animation.naturalHeight || animation.height,
      valueDisplay: getComputedStyle(document.getElementById('miniValue')).display,
      valueOpacity: Number.parseFloat(getComputedStyle(document.getElementById('miniValue')).opacity),
      valueX: value.left - capsule.left,
      valueY: value.top - capsule.top,
      valueWidth: value.width,
      valueHeight: value.height,
      source: "procedural",
      proceduralState: catCanvas.dataset.state || ""
    };
  })()`, true);
  const expectedPetStates = taskMode === "attention"
    ? ["waiting_auth", "waiting"]
    : taskMode === "working"
      ? ["running", "thinking"]
      : ["idle", "curious", "grooming", "stretch", "sleeping", "wave", "hop"];
  const expectedPetSource = petLayout.source === "procedural"
    && expectedPetStates.includes(petLayout.proceduralState);
  const transientMonitorPet = pet === "cat" || pet === "fox";
  const idleMonitorInvalid = !taskMode && (
    transientMonitorPet
      ? petLayout.valueOpacity > 0.05
      : petLayout.valueDisplay === "none"
        || Math.abs(petLayout.valueX - displayX) > 0.25
        || Math.abs(petLayout.valueY - displayY) > 0.25
        || Math.abs(petLayout.valueWidth - displayWidth) > 0.25
        || Math.abs(petLayout.valueHeight - displayHeight) > 0.25
  );
  if (Math.abs(petLayout.width - 216) > 0.25
      || Math.abs(petLayout.height - 129.6) > 0.25
      || Math.abs(petLayout.imageDX) > 0.25
      || Math.abs(petLayout.imageDY) > 0.25
      || Math.abs(petLayout.imageWidth - 216) > 0.25
      || Math.abs(petLayout.imageHeight - 129.6) > 0.25
      || petLayout.naturalWidth !== 480
      || petLayout.naturalHeight !== 288
      || !expectedPetSource
      || (taskMode && petLayout.valueDisplay === "none")
      || (taskMode && petLayout.valueOpacity < 0.95)
      || idleMonitorInvalid) {
    throw new Error(`pet mini layout/state mismatch: ${JSON.stringify({ style, taskMode, ...petLayout })}`);
  }
  if (pet === "cat") {
    const firstFrame = await window.webContents.executeJavaScript(
      `document.getElementById("petCatCanvas").toDataURL()`,
      true
    );
    await wait(140);
    const nextFrame = await window.webContents.executeJavaScript(
      `document.getElementById("petCatCanvas").toDataURL()`,
      true
    );
    if (firstFrame === nextFrame) {
      throw new Error(`procedural cat did not advance continuously: ${JSON.stringify({ style, taskMode })}`);
    }
  }
  if (taskMode && pet === "dino" && !activityStyle && !theme) {
    const activeQuota = await window.webContents.executeJavaScript(`(() => {
      const startedAt = Date.now() - 5500;
      render({
        ...currentState,
        task: { ...currentState.task, state: "${taskMode}", startedAt }
      });
      return {
        value: document.getElementById("miniValue").textContent,
        quotaPage: document.getElementById("capsule").classList.contains("pet-quota-page")
      };
    })()`, true);
    if (!activeQuota.quotaPage || activeQuota.value !== "额度98%") {
      throw new Error(`account mini monitor did not rotate current quota: ${JSON.stringify({ taskMode, activeQuota })}`);
    }
    await wait(280);
  }
  const image = await window.webContents.capturePage();
  const suffix = [pet === "dino" ? null : pet, theme, activityStyle, taskMode].filter(Boolean).map((value) => `-${value}`).join("");
  fs.writeFileSync(path.join(outputDirectory, `mini-${style}${suffix}@2x.png`), image.toPNG());

  if (style === "quota" && !taskMode) {
    window.webContents.sendInputEvent({ type: "mouseDown", x: 350, y: 26, button: "left", clickCount: 1 });
    window.webContents.sendInputEvent({ type: "mouseUp", x: 350, y: 26, button: "left", clickCount: 1 });
    await wait(850);
    const interaction = await window.webContents.executeJavaScript(`({
      isMini: document.documentElement.classList.contains("mini-mode"),
      isExpanded: document.getElementById("capsule").getAttribute("aria-expanded"),
      miniStyle: document.getElementById("capsule").dataset.miniStyle
    })`, true);
    if (!interaction.isMini || interaction.isExpanded !== "false" || interaction.miniStyle !== "tokens") {
      throw new Error(`idle mini single click did not cycle its display: ${JSON.stringify(interaction)}`);
    }
  }
}

async function assertOrbPet() {
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
      additionalArguments: ["--fixture=large-token"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(300);
  await window.webContents.executeJavaScript(`
    document.querySelector('#petCharacterMenu [data-value="orb"]').click();
    document.querySelector('#miniStyleMenu [data-value="quota"]').click();
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
  `, true);
  await wait(700);

  const result = await window.webContents.executeJavaScript(`(() => {
    const capsule = document.getElementById("miniCapsule").getBoundingClientRect();
    const orb = document.querySelector(".pet-orb");
    const orbRect = orb.getBoundingClientRect();
    const orbStyle = getComputedStyle(orb);
    const orbCenterHit = isMiniOrbPointerHit({
      clientX: orbRect.left + orbRect.width / 2,
      clientY: orbRect.top + orbRect.height / 2
    });
    const transparentCanvasHit = isMiniOrbPointerHit({
      clientX: capsule.left + 3,
      clientY: capsule.top + 3
    });
    const pages = [];
    const values = [];
    for (let index = 0; index < 5; index += 1) {
      pages.push(document.getElementById("capsule").dataset.miniStyle);
      values.push(document.getElementById("miniValue").textContent);
      if (index < 4) cycleMiniDisplay();
    }
    render({
      ...currentState,
      task: { state: "working", label: "思考中", startedAt: Date.now() }
    });
    const activePage = document.getElementById("capsule").dataset.miniStyle;
    handleMiniSingleClick();
    return {
      display: getComputedStyle(orb).display,
      width: parseFloat(orbStyle.width),
      height: parseFloat(orbStyle.height),
      x: parseFloat(orbStyle.left),
      y: parseFloat(orbStyle.top),
      renderedWidth: orbRect.width,
      renderedX: orbRect.left - capsule.left,
      centerBackground: orbStyle.backgroundColor,
      orbStyle: document.getElementById("capsule").dataset.orbStyle,
      borderWidth: orbStyle.borderWidth,
      statusPresent: document.getElementById("petOrbStatus") !== null,
      orbCenterHit,
      transparentCanvasHit,
      growthScale: getComputedStyle(document.documentElement)
        .getPropertyValue("--pet-growth-scale").trim(),
      pages,
      values,
      activePage,
      activePageAfterClick: document.getElementById("capsule").dataset.miniStyle,
      conversationExpanded: document.documentElement.classList.contains("mini-conversation-expanded"),
      roamEligible: petRoamIsEligible()
    };
  })()`, true);

  if (result.display === "none"
      || Math.abs(result.width - 62) > 0.25
      || Math.abs(result.height - 62) > 0.25
      || Math.abs(result.x - 77) > 0.25
      || Math.abs(result.y - 33.8) > 0.25
      || result.orbStyle !== "1"
      || result.borderWidth !== "0px"
      || result.statusPresent
      || !result.orbCenterHit
      || result.transparentCanvasHit
      || Number(result.growthScale) !== 1
      || JSON.stringify(result.pages) !== JSON.stringify(["quota", "tokens", "weather", "temperature", "time"])
      || result.activePage === result.activePageAfterClick
      || result.conversationExpanded
      || result.roamEligible) {
    throw new Error(`small orb behavior or layout drifted: ${JSON.stringify(result)}`);
  }

  await window.webContents.executeJavaScript(
    `document.body.style.background = "#f6f8fb"`,
    true
  );
  const orbVariants = ["orb", "orb_2", "orb_3", "orb_4"];
  for (let index = 0; index < orbVariants.length; index += 1) {
    const character = orbVariants[index];
    const style = String(index + 1);
    const variant = await window.webContents.executeJavaScript(`(() => {
      selectPetCharacter("${character}");
      render({
        ...currentState,
        task: { state: "idle", label: "空闲", startedAt: Date.now() }
      });
      const orb = document.querySelector(".pet-orb");
      const rect = orb.getBoundingClientRect();
      return {
        pet: document.getElementById("capsule").dataset.pet,
        style: document.getElementById("capsule").dataset.orbStyle,
        width: rect.width,
        height: rect.height,
        growthScale: getComputedStyle(document.documentElement)
          .getPropertyValue("--pet-growth-scale").trim(),
        roamEligible: petRoamIsEligible(),
        centerHit: isMiniOrbPointerHit({
          clientX: rect.left + rect.width / 2,
          clientY: rect.top + rect.height / 2
        })
      };
    })()`, true);
    if (variant.pet !== character
        || variant.style !== style
        || Math.abs(variant.width - 62) > 0.25
        || Math.abs(variant.height - 62) > 0.25
        || Number(variant.growthScale) !== 1
        || variant.roamEligible
        || !variant.centerHit) {
      throw new Error(`small orb ${style} drifted: ${JSON.stringify(variant)}`);
    }
    await wait(220);
    const variantImage = await window.webContents.capturePage();
    fs.writeFileSync(
      path.join(outputDirectory, `mini-orb-style-${style}@2x.png`),
      variantImage.toPNG()
    );
  }

  await window.webContents.executeJavaScript(`selectPetCharacter("orb")`, true);
  await wait(120);
  const tokenLayout = await window.webContents.executeJavaScript(`(() => {
    orbPagePreference = "tokens";
    applyMiniStylePreference();
    render({
      ...currentState,
      task: { state: "idle", label: "空闲", startedAt: Date.now() }
    });
    const value = document.getElementById("miniValue");
    return {
      number: value.textContent,
      unit: value.dataset.unit || "",
      fontSize: parseFloat(getComputedStyle(value).fontSize)
    };
  })()`, true);
  if (/[KMB]$/.test(tokenLayout.number)
      || !/^[KMB]$/.test(tokenLayout.unit)
      || tokenLayout.fontSize < 12) {
    throw new Error(`small orb token unit layout drifted: ${JSON.stringify(tokenLayout)}`);
  }
  await wait(360);
  const tokenImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-orb-token-unit@2x.png"),
    tokenImage.toPNG()
  );
  await window.webContents.executeJavaScript(`(() => {
    orbPagePreference = "quota";
    applyMiniStylePreference();
    render({
      ...currentState,
      task: { state: "idle", label: "空闲", startedAt: Date.now() }
    });
  })()`, true);

  for (const mode of ["idle", "working", "attention"]) {
    await window.webContents.executeJavaScript(`
      render({
        ...currentState,
        task: {
          state: "${mode}",
          label: "${mode === "attention" ? "等待授权" : mode === "working" ? "思考中" : "空闲"}",
          startedAt: Date.now()
        }
      });
    `, true);
    await wait(260);
    const image = await window.webContents.capturePage();
    fs.writeFileSync(
      path.join(outputDirectory, `mini-orb-${mode}@2x.png`),
      image.toPNG()
    );
  }
  await window.webContents.executeJavaScript(`
    render({
      ...currentState,
      task: { state: "idle", label: "空闲", startedAt: Date.now() }
    });
  `, true);
  await window.webContents.executeJavaScript(
    `document.body.style.background = "#f6f8fb"`,
    true
  );
  await wait(80);
  const lightImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-orb-light-desktop@2x.png"),
    lightImage.toPNG()
  );
  await window.webContents.executeJavaScript(
    `document.body.style.background = "linear-gradient(135deg, #d9f3f5 0%, #72cbd6 48%, #dceeff 100%)"`,
    true
  );
  await wait(80);
  const colorDesktopImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-orb-color-desktop@2x.png"),
    colorDesktopImage.toPNG()
  );
  await window.webContents.executeJavaScript(`
    render({
      ...currentState,
      limits: (currentState.limits || []).map((limit, index) => (
        index === 0 ? { ...limit, remainingPercent: 33 } : limit
      )),
      task: { state: "idle", label: "空闲", startedAt: Date.now() }
    });
  `, true);
  await wait(420);
  const lowQuotaImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-orb-low-quota@2x.png"),
    lowQuotaImage.toPNG()
  );
}

async function assertPetDesktopInteraction() {
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
      additionalArguments: ["--fixture=pet-roam"]
    }
  });
  captureWindows.push(window);

  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(250);
  await window.webContents.executeJavaScript(`
    Math.random = () => 0;
    document.querySelector('#petCharacterMenu [data-value="fox"]').click();
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
  `, true);
  await wait(5300);
  const interaction = await window.webContents.executeJavaScript(`(() => {
    const canvas = document.getElementById("petCatCanvas");
    return {
      isMini: document.documentElement.classList.contains("mini-mode"),
      state: canvas.dataset.state || "",
      width: canvas.getBoundingClientRect().width,
      height: canvas.getBoundingClientRect().height
    };
  })()`, true);
  if (!interaction.isMini
      || interaction.state !== "pawing"
      || Math.abs(interaction.width - 216) > .25
      || Math.abs(interaction.height - 129.6) > .25) {
    throw new Error(`desktop interaction choreography did not become visible: ${JSON.stringify(interaction)}`);
  }
  const image = await window.webContents.capturePage();
  fs.writeFileSync(path.join(outputDirectory, "mini-fox-desktop-pawing@2x.png"), image.toPNG());

  window.webContents.send("pulse:pet-drop", { kind: "dock", direction: "right" });
  await wait(1100);
  const manualDock = await window.webContents.executeJavaScript(`(() => {
    const canvas = document.getElementById("petCatCanvas");
    return {
      state: canvas.dataset.state || "",
      facesLeft: canvas.dataset.facesLeft || ""
    };
  })()`, true);
  if (manualDock.state !== "pouncing" || manualDock.facesLeft === "true") {
    throw new Error(`manual taskbar drop did not start dock interaction: ${JSON.stringify(manualDock)}`);
  }

  const wakeStarted = await window.webContents.executeJavaScript(`(() => {
    cancelPetRoam();
    catIdleState = "sleeping";
    catIdleStateUntil = Date.now() + 10000;
    petRoamingState = "sleeping";
    proceduralCat.setState("sleeping");
    return {
      consumed: wakeSleepingPetFromClick(),
      state: document.getElementById("petCatCanvas").dataset.state || ""
    };
  })()`, true);
  if (!wakeStarted.consumed || wakeStarted.state !== "stretch") {
    throw new Error(`sleeping pet did not enter click-to-wake stretch: ${JSON.stringify(wakeStarted)}`);
  }
  await wait(2100);
  const heldStretch = await window.webContents.executeJavaScript(
    `document.getElementById("petCatCanvas").dataset.state || ""`,
    true
  );
  if (heldStretch !== "stretch") {
    throw new Error(`click-to-wake stretch ended before two seconds: ${heldStretch}`);
  }
  await wait(650);
  const wokeState = await window.webContents.executeJavaScript(
    `document.getElementById("petCatCanvas").dataset.state || ""`,
    true
  );
  if (wokeState !== "idle") {
    throw new Error(`click-to-wake stretch did not settle naturally: ${wokeState}`);
  }
  window.destroy();
}

async function assertFootstepImpactEffect() {
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
      additionalArguments: ["--fixture=pet-roam"]
    }
  });
  captureWindows.push(window);

  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(250);
  await window.webContents.executeJavaScript(`
    document.querySelector('#petCharacterMenu [data-value="cat"]').click();
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
  `, true);
  await wait(850);
  const baseline = await window.webContents.executeJavaScript(`(() => {
    cancelPetRoam();
    petRoamingState = "idle";
    proceduralCat.setState("idle");
    const canvas = document.getElementById("petCatCanvas");
    const pixels = canvas.getContext("2d").getImageData(0, 222, 30, 55).data;
    return Array.from(pixels).filter((_, index) => index % 4 === 3 && pixels[index] > 8).length;
  })()`, true);
  const impactGeometry = await window.webContents.executeJavaScript(`(() => {
    const canvas = document.getElementById("petCatCanvas");
    const context = canvas.getContext("2d");
    proceduralCat.renderFootstepImpactForQA(.09);
    const pixels = context.getImageData(150, 218, 120, 62).data;
    return {
      visiblePixels: Array.from(pixels)
        .filter((_, index) => index % 4 === 3 && pixels[index] > 12).length
    };
  })()`, true);
  if (impactGeometry.visiblePixels < 220) {
    throw new Error(`footstep contact decal was not visible: ${JSON.stringify(impactGeometry)}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "footstep-impact-geometry.json"),
    JSON.stringify(impactGeometry, null, 2)
  );
  await window.webContents.executeJavaScript(`
    proceduralCat.setFacesLeft(false);
    proceduralCat.renderFrameForQA("walk_right", ${1 / 1.12 / 2 - 0.01});
  `, true);
  await wait(30);
  const beforeImpactImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-cat-footstep-before-contact@2x.png"),
    beforeImpactImage.toPNG()
  );
  await window.webContents.executeJavaScript(`
    proceduralCat.renderFrameForQA("walk_right", ${1 / 1.12 / 2 + 0.09});
  `, true);
  await wait(30);
  const impact = await window.webContents.executeJavaScript(`(() => {
    const canvas = document.getElementById("petCatCanvas");
    const pixels = canvas.getContext("2d").getImageData(0, 222, 30, 55).data;
    return {
      state: canvas.dataset.state || "",
      visiblePixels: Array.from(pixels)
        .filter((_, index) => index % 4 === 3 && pixels[index] > 8).length
    };
  })()`, true);
  if (impact.state !== "walk_right" || impact.visiblePixels <= baseline + 8) {
    throw new Error(`walking footstep impact was not visible behind the pet: ${JSON.stringify({ baseline, impact })}`);
  }
  const compressedImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-cat-footstep-contact@2x.png"),
    compressedImage.toPNG()
  );
  await window.webContents.executeJavaScript(`
    proceduralCat.renderFrameForQA("walk_right", ${1 / 1.12 / 2 + 0.27});
  `, true);
  await wait(30);
  const fracturedImage = await window.webContents.capturePage();
  fs.writeFileSync(
    path.join(outputDirectory, "mini-cat-footstep-settle@2x.png"),
    fracturedImage.toPNG()
  );
  await window.webContents.executeJavaScript(`
    proceduralCat.setVisible(false);
    proceduralCat.setVisible(true);
    proceduralCat.setState("walk_right");
  `, true);
  const frameStats = await window.webContents.executeJavaScript(`new Promise((resolve) => {
    const samples = [];
    let previous = performance.now();
    const tick = (now) => {
      samples.push(now - previous);
      previous = now;
      if (samples.length < 72) {
        requestAnimationFrame(tick);
        return;
      }
      const sorted = samples.slice(8).sort((left, right) => left - right);
      resolve({
        frameCount: samples.length,
        p95: sorted[Math.floor(sorted.length * .95)] || 0
      });
    };
    requestAnimationFrame(tick);
  })`, true);
  if (frameStats.frameCount < 72 || frameStats.p95 > 28) {
    throw new Error(`walking footstep effect missed the smooth-frame budget: ${JSON.stringify(frameStats)}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "mini-cat-footstep-impact@2x.png"),
    compressedImage.toPNG()
  );
  window.destroy();
}

async function assertLiveTokenRoll() {
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
      additionalArguments: ["--fixture=large-token"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(300);
  await window.webContents.executeJavaScript(`render({
    ...currentState,
    task: { state: "working", label: "思考中", startedAt: Date.now() },
    usage: { ...currentState.usage, today: 153200000 }
  })`, true);
  await wait(260);
  await window.webContents.executeJavaScript(`render({
    ...currentState,
    usage: { ...currentState.usage, today: 153300000 }
  })`, true);
  await wait(45);
  const midFrame = await window.webContents.executeJavaScript(`(() => ({
    value: document.getElementById("todayTokens").textContent,
    previous: document.getElementById("todayTokensPrevious").textContent,
    previousVisible: !document.getElementById("todayTokensPrevious").hidden,
    activeAnimations: document.querySelector(".token-roll-viewport").getAnimations({ subtree: true }).length
  }))()`, true);
  if (midFrame.value !== "153.3M"
      || midFrame.previous !== "153.2M"
      || !midFrame.previousVisible
      || midFrame.activeAnimations < 2) {
    throw new Error(`live Token roll did not animate upward: ${JSON.stringify(midFrame)}`);
  }
  await wait(240);
  const settled = await window.webContents.executeJavaScript(`(() => {
    const current = document.getElementById("todayTokens");
    const previous = document.getElementById("todayTokensPrevious");
    return {
      previousHidden: previous.hidden,
      previousDisplay: getComputedStyle(previous).display,
      value: current.textContent,
      currentTransform: getComputedStyle(current).transform,
      activeAnimations: document.querySelector(".token-roll-viewport").getAnimations({ subtree: true }).length
    };
  })()`, true);
  if (!settled.previousHidden
      || settled.previousDisplay !== "none"
      || settled.value !== "153.3M"
      || settled.currentTransform !== "none"
      || settled.activeAnimations !== 0) {
    throw new Error(`live Token roll did not settle cleanly: ${JSON.stringify(settled)}`);
  }
  window.destroy();
}

async function assertOfflineAPIMiniTime() {
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
      partition: `offline-api-mini-${Date.now()}`,
      additionalArguments: ["--fixture=api-rain"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(300);
  const result = await window.webContents.executeJavaScript(`new Promise((resolve) => {
    apiMiniStylePreference = "time";
    localStorage.setItem("codexPulse.apiMiniStyle", "time");
    render(currentState);
    const before = {
      auth: currentState?.account?.auth,
      style: effectiveMiniStyle(currentState),
      storedMode: localStorage.getItem("codexPulse.lastUsageMode")
    };
    render({
      ...currentState,
      connection: "offline",
      account: { ...currentState.account, auth: "—" },
      message: "正在重新连接"
    });
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
    setTimeout(() => resolve({
      style: document.getElementById("capsule").dataset.miniStyle,
      value: document.getElementById("miniValue").textContent,
      color: document.getElementById("miniCapsule").style.getPropertyValue("--mini-color").trim(),
      idle: document.getElementById("capsule").classList.contains("pet-idle"),
      before,
      storedMode: localStorage.getItem("codexPulse.lastUsageMode")
    }), 350);
  })`, true);
  if (result.style !== "time" || !/^\d{2}:\d{2}$/.test(result.value)
      || result.color !== "var(--blue)" || !result.idle) {
    throw new Error(`offline API mini did not preserve time: ${JSON.stringify(result)}`);
  }
  window.destroy();
}

async function assertTaskConversationIsland() {
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
  await wait(320);
  const weatherStripSize = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("informationStrip").getBoundingClientRect();
    return { width: rect.width, height: rect.height };
  })()`, true);
  await window.webContents.executeJavaScript(`render({
    ...currentState,
    task: {
      state: "working",
      label: "思考中",
      title: "正在输出回复",
      startedAt: Date.now(),
      threadID: "thread-visual",
      conversation: [
        { id: "user-1", role: "user", text: "请优化这个交互", isStreaming: false },
        { id: "assistant-1", role: "assistant", text: "我正在检查当前的窗口状态，并持续把最新的流式输出滚动到任务信息栏末尾", isStreaming: true }
      ]
    }
  })`, true);
  await wait(260);
  const collapsed = await window.webContents.executeJavaScript(`(() => {
    const strip = document.getElementById("informationStrip").getBoundingClientRect();
    const content = document.getElementById("informationTaskContent").getBoundingClientRect();
    const copy = document.querySelector(".information-task-copy").getBoundingClientRect();
    return {
      taskMode: document.getElementById("informationStrip").classList.contains("task-streaming"),
      disabled: document.getElementById("informationStrip").disabled,
      summary: document.getElementById("informationTaskSummary").textContent,
      summaryScrollLeft: document.getElementById("informationTaskSummary").scrollLeft,
      stripWidth: strip.width,
      stripHeight: strip.height,
      leftInset: content.left - strip.left,
      rightInset: strip.right - content.right,
      copyCenterDelta: Math.abs((copy.left + copy.width / 2) - (strip.left + strip.width / 2)),
      capsuleWidth: document.getElementById("capsule").getBoundingClientRect().width
    };
  })()`, true);
  if (!collapsed.taskMode || collapsed.disabled
      || !collapsed.summary.includes("检查当前的窗口状态")
      || collapsed.summaryScrollLeft <= 0
      || Math.abs(collapsed.stripWidth - weatherStripSize.width) > .5
      || Math.abs(collapsed.stripHeight - weatherStripSize.height) > .5
      || collapsed.leftInset < 8.5 || collapsed.rightInset < 8.5
      || collapsed.copyCenterDelta > .75
      || Math.abs(collapsed.capsuleWidth - 275) > .5) {
    throw new Error(`task stream strip changed size before click: ${JSON.stringify({ weatherStripSize, collapsed })}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "task-information-stream-collapsed@2x.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`document.getElementById("informationStrip").click()`, true);
  await wait(90);
  const morphing = await window.webContents.executeJavaScript(`(() => {
    const detail = document.getElementById("conversationDetail");
    const matrix = new DOMMatrixReadOnly(getComputedStyle(detail).transform);
    return {
      scaleX: matrix.a,
      scaleY: matrix.d,
      translateY: matrix.f,
      backdropFilter: getComputedStyle(detail).backdropFilter
    };
  })()`, true);
  if (Math.abs(morphing.scaleX - 1) > .001
      || Math.abs(morphing.scaleY - 1) > .001
      || morphing.translateY < -6.01
      || morphing.translateY > .01
      || morphing.backdropFilter !== "none") {
    throw new Error(`task conversation restored a scaled glass layer: ${JSON.stringify(morphing)}`);
  }
  await wait(290);
  const opened = await window.webContents.executeJavaScript(`(() => {
    const detail = document.getElementById("conversationDetail");
    const strip = document.getElementById("informationStrip").getBoundingClientRect();
    const rect = detail.getBoundingClientRect();
    return {
      hidden: detail.hidden,
      open: detail.classList.contains("open"),
      expanded: document.getElementById("informationStrip").getAttribute("aria-expanded"),
      width: rect.width,
      height: rect.height,
      islandGap: rect.top - strip.bottom,
      stripWidth: strip.width,
      messages: document.querySelectorAll(".conversation-message").length
    };
  })()`, true);
  if (opened.hidden || !opened.open || opened.expanded !== "true"
      || Math.abs(opened.width - 342) > .5 || Math.abs(opened.height - 270) > .5
      || Math.abs(opened.stripWidth - 342) > .5
      || Math.abs(opened.islandGap - 6) > .5
      || opened.messages !== 2) {
    throw new Error(`task conversation did not open as one non-overlapping surface: ${JSON.stringify(opened)}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "task-information-island@2x.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  await window.webContents.executeJavaScript(`render({
    ...currentState,
    task: {
      ...currentState.task,
      conversation: [
        currentState.task.conversation[0],
        { ...currentState.task.conversation[1], text: "我正在检查当前的窗口状态，并实时更新完整回复" }
      ]
    }
  })`, true);
  await wait(80);
  const streamed = await window.webContents.executeJavaScript(
    `document.querySelector(".conversation-message.assistant .conversation-message-text").textContent`,
    true
  );
  if (!streamed.endsWith("实时更新完整回复")) {
    throw new Error(`expanded conversation did not stream in place: ${streamed}`);
  }

  await window.webContents.executeJavaScript(`render({
    ...currentState,
    task: { state: "idle", label: "空闲", title: null, project: null, startedAt: null, conversation: [] }
  })`, true);
  await wait(380);
  const restored = await window.webContents.executeJavaScript(`(() => ({
    conversationHidden: document.getElementById("conversationDetail").hidden,
    taskMode: document.getElementById("informationStrip").classList.contains("task-streaming"),
    weatherVisible: document.getElementById("informationWeatherContent").getAttribute("aria-hidden"),
    expanded: document.getElementById("informationStrip").getAttribute("aria-expanded")
  }))()`, true);
  if (!restored.conversationHidden || restored.taskMode
      || restored.weatherVisible !== "false" || restored.expanded !== "false") {
    throw new Error(`task conversation did not retract to weather: ${JSON.stringify(restored)}`);
  }
  window.destroy();
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
        const petRow = document.querySelector(".pet-preference-row");
        const container = document.getElementById("appearanceSettings");
        const rowRect = row.getBoundingClientRect();
        const petRect = petRow.getBoundingClientRect();
        const containerRect = container.getBoundingClientRect();
        resolve({
          hidden: container.hidden,
          display: getComputedStyle(row).display,
          height: rowRect.height,
          inside: rowRect.top >= containerRect.top && rowRect.bottom <= containerRect.bottom,
          label: document.getElementById("miniStyleLabel").textContent,
          petDisplay: getComputedStyle(petRow).display,
          petInside: petRect.top >= containerRect.top && petRect.bottom <= containerRect.bottom,
          petLabel: document.getElementById("petCharacterLabel").textContent,
          updateRowRemoved: document.querySelector(".update-preference-row") === null
        });
      }));
    }, 280);
  })`, true);
  if (result.hidden || result.display === "none" || result.height < 28 || !result.inside || !result.label
      || result.petDisplay === "none" || !result.petInside || !result.petLabel
      || !result.updateRowRemoved) {
    throw new Error(`mini settings picker is not visible: ${JSON.stringify(result)}`);
  }
  await wait(150);
  const image = await window.webContents.capturePage();
  fs.writeFileSync(path.join(outputDirectory, "clear-settings@2x.png"), image.toPNG());
}

async function assertAPIMiniStyleRules() {
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
      additionalArguments: ["--fixture=api-rain"]
    }
  });
  captureWindows.push(window);
  const pagePath = path.resolve(__dirname, "../src/renderer/index.html");
  await window.loadFile(pagePath);
  await window.webContents.executeJavaScript(`localStorage.removeItem("codexPulse.apiMiniStyle")`, true);
  await window.reload();
  await wait(450);
  const initial = await window.webContents.executeJavaScript(`(() => {
    const quota = document.querySelector('#miniStyleMenu [data-value="quota"]');
    const visible = [...document.querySelectorAll('#miniStyleMenu .preference-option')]
      .filter((option) => !option.hidden)
      .map((option) => option.dataset.value);
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
    return {
      label: document.getElementById("miniStyleLabel").textContent,
      style: document.getElementById("capsule").dataset.miniStyle,
      quotaHidden: quota.hidden,
      visible,
      accountStyle: localStorage.getItem("codexPulse.miniStyle"),
      apiStyle: localStorage.getItem("codexPulse.apiMiniStyle")
    };
  })()`, true);
  await wait(300);
  const monitorText = await window.webContents.executeJavaScript(
    `document.getElementById("miniValue").textContent`,
    true
  );
  if (initial.label !== "当地时间"
      || initial.style !== "time"
      || !initial.quotaHidden
      || JSON.stringify(initial.visible) !== JSON.stringify(["tokens", "status", "weather", "time"])
      || initial.apiStyle !== "time"
      || !/^\d{2}:\d{2}$/.test(monitorText)) {
    throw new Error(`API mini styles did not default to time: ${JSON.stringify({ initial, monitorText })}`);
  }
  const selected = await window.webContents.executeJavaScript(`(() => {
    document.querySelector('#miniStyleMenu [data-value="tokens"]').click();
    return {
      label: document.getElementById("miniStyleLabel").textContent,
      style: document.getElementById("capsule").dataset.miniStyle,
      apiStyle: localStorage.getItem("codexPulse.apiMiniStyle")
    };
  })()`, true);
  if (selected.label !== "今日 Token" || selected.style !== "tokens" || selected.apiStyle !== "tokens") {
    throw new Error(`API mini style selection was not persisted: ${JSON.stringify(selected)}`);
  }
  const activeMonitor = await window.webContents.executeJavaScript(`(() => {
    const startedAt = Date.now();
    renderMini({
      ...currentState,
      limits: [{ name: "模拟额度", remainingPercent: 42 }],
      task: { state: "working", label: "思考中", startedAt }
    }, new Date(startedAt + 5500));
    return {
      value: document.getElementById("miniValue").textContent,
      quotaPage: document.getElementById("capsule").classList.contains("pet-quota-page")
    };
  })()`, true);
  if (activeMonitor.quotaPage || activeMonitor.value.startsWith("额度")) {
    throw new Error(`API mini monitor must not rotate account quota: ${JSON.stringify(activeMonitor)}`);
  }
}

async function assertUpdateReminderInteraction() {
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
      additionalArguments: ["--fixture=update"]
    }
  });
  captureWindows.push(window);
  await window.loadFile(path.resolve(__dirname, "../src/renderer/index.html"));
  await wait(450);

  const collapsed = await window.webContents.executeJavaScript(`(() => {
    const capsule = document.getElementById("capsule").getBoundingClientRect();
    const indicator = document.getElementById("updateIndicator");
    return {
      capsuleWidth: capsule.width,
      indicatorHidden: indicator.hidden,
      indicatorTitle: indicator.title,
      expandedWidth: Number(document.getElementById("capsule").dataset.expandedWidth)
    };
  })()`, true);
  if (collapsed.indicatorHidden
      || !collapsed.indicatorTitle.includes("v0.1.27")
      || collapsed.expandedWidth < 303
      || collapsed.capsuleWidth < 303) {
    throw new Error(`update reminder did not reserve adaptive capsule space: ${JSON.stringify(collapsed)}`);
  }

  await window.webContents.executeJavaScript(`document.getElementById("updateIndicator").click()`, true);
  await wait(520);
  const detail = await window.webContents.executeJavaScript(`(() => ({
    expanded: document.getElementById("capsule").getAttribute("aria-expanded"),
    updateMode: document.getElementById("detail").classList.contains("update-mode"),
    updateHidden: document.getElementById("updateDetail").hidden,
    standardHeaderDisplay: getComputedStyle(document.querySelector(".account-row")).display,
    version: document.getElementById("updateVersionRoute").textContent,
    title: document.getElementById("updateReleaseTitle").textContent,
    notes: document.getElementById("updateReleaseNotes").textContent,
    installText: document.getElementById("installUpdateButton").textContent,
    skipText: document.getElementById("skipUpdateButton").textContent
  }))()`, true);
  if (detail.expanded !== "true"
      || !detail.updateMode
      || detail.updateHidden
      || detail.standardHeaderDisplay !== "none"
      || !detail.version.includes("0.1.26")
      || !detail.version.includes("0.1.27")
      || detail.title !== "CodexPulse v0.1.27"
      || !detail.notes.includes("磁吸跟随")
      || !detail.notes.includes("• 解决双击缩小")
      || detail.installText !== "立即更新"
      || detail.skipText !== "跳过此版本") {
    throw new Error(`update detail interaction is incomplete: ${JSON.stringify(detail)}`);
  }
  const image = await window.webContents.capturePage({ x: 0, y: 0, width: 390, height: 410 });
  fs.writeFileSync(path.join(outputDirectory, "update-detail@2x.png"), image.toPNG());

  await window.webContents.executeJavaScript(`document.getElementById("installUpdateButton").click()`, true);
  await wait(70);
  const downloading = await window.webContents.executeJavaScript(`(() => ({
    progressHidden: document.getElementById("updateProgress").hidden,
    status: document.getElementById("updateProgressStatus").textContent,
    label: document.getElementById("updateProgressLabel").textContent,
    size: document.getElementById("updateProgressSize").textContent,
    fill: parseFloat(document.getElementById("updateProgressFill").style.width),
    installText: document.getElementById("installUpdateButton").textContent,
    installDisabled: document.getElementById("installUpdateButton").disabled,
    skipDisabled: document.getElementById("skipUpdateButton").disabled
  }))()`, true);
  if (downloading.progressHidden
      || !downloading.status.includes("正在下载")
      || downloading.label !== "42%"
      || downloading.size !== "42.0 MB / 100.0 MB"
      || Math.abs(downloading.fill - 42) > .1
      || downloading.installText !== "下载中 42%"
      || !downloading.installDisabled
      || !downloading.skipDisabled) {
    throw new Error(`update download progress is incomplete: ${JSON.stringify(downloading)}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "update-download-progress@2x.png"),
    (await window.webContents.capturePage({ x: 0, y: 0, width: 390, height: 470 })).toPNG()
  );

  await wait(180);
  const ready = await window.webContents.executeJavaScript(`(() => ({
    label: document.getElementById("updateProgressLabel").textContent,
    status: document.getElementById("updateProgressStatus").textContent,
    installText: document.getElementById("installUpdateButton").textContent,
    installDisabled: document.getElementById("installUpdateButton").disabled,
    skipDisabled: document.getElementById("skipUpdateButton").disabled
  }))()`, true);
  if (ready.label !== "完成"
      || !ready.status.includes("下载完成")
      || ready.installText !== "重启并更新"
      || ready.installDisabled
      || ready.skipDisabled) {
    throw new Error(`downloaded update did not enter restart-ready state: ${JSON.stringify(ready)}`);
  }

  await window.webContents.executeJavaScript(`document.getElementById("skipUpdateButton").click()`, true);
  await wait(520);
  const skipped = await window.webContents.executeJavaScript(`(() => ({
    expanded: document.getElementById("capsule").getAttribute("aria-expanded"),
    indicatorHidden: document.getElementById("updateIndicator").hidden,
    hasUpdateClass: document.getElementById("capsule").classList.contains("has-update"),
    capsuleWidth: document.getElementById("capsule").getBoundingClientRect().width
  }))()`, true);
  if (skipped.expanded !== "false"
      || !skipped.indicatorHidden
      || skipped.hasUpdateClass
      || skipped.capsuleWidth !== 275) {
    throw new Error(`skipped update remained visible: ${JSON.stringify(skipped)}`);
  }
  window.destroy();
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
  // User preferences persist between BrowserWindows in one Electron session;
  // keep this geometry test deterministic even when the local app currently
  // uses the taller black-hole companion.
  await window.webContents.executeJavaScript(
    `document.querySelector('#petCharacterMenu [data-value="dino"]').click()`,
    true
  );
  await wait(80);
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
    throw new Error(`mini transition did not stay on the compositor morph layer: ${JSON.stringify(activeMiniTransition)}`);
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
  if (bounds.width !== 390 || bounds.height !== 810) {
    throw new Error(`mini mode changed the stable native surface: ${JSON.stringify(bounds)}`);
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
  const expectedMiniLeft = miniLayout.viewport.width - 228;
  if (Math.abs(miniLayout.capsule.width - 216) > 0.5
      || Math.abs(miniLayout.capsule.height - 129.6) > 0.5
      || Math.abs(miniLayout.capsule.left - expectedMiniLeft) > 0.5
      || Math.abs(miniLayout.capsule.top - 12) > 0.5
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
      || Math.abs(afterDesktopBlur.capsuleWidth - 216) > 0.5
      || afterBlurBounds.width !== 390
      || afterBlurBounds.height !== 810) {
    throw new Error(`desktop blur restored the full capsule: ${JSON.stringify({ afterDesktopBlur, afterBlurBounds })}`);
  }

  // Match the macOS event contract: a second double-click restores the full
  // collapsed capsule. Neither path may leave a pending single-click behind.
  const miniCenterX = 350;
  const miniCenterY = 26;
  click(2, miniCenterX, miniCenterY);
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

  const petBeforeConversation = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById('capsule').getBoundingClientRect();
    return { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
  })()`, true);
  await window.webContents.executeJavaScript(`render({
    ...currentState,
    task: {
      state: "working",
      label: "思考中",
      title: "正在输出回复",
      startedAt: Date.now(),
      conversation: [
        { id: "mini-user", role: "user", text: "保留宠物并展开对话", isStreaming: false },
        { id: "mini-assistant", role: "assistant", text: "正在实时处理", isStreaming: true }
      ]
    }
  })`, true);
  click(1, miniCenterX, miniCenterY);
  await wait(720);
  const expandedFromMini = await window.webContents.executeJavaScript(`(() => {
    const pet = document.getElementById('capsule').getBoundingClientRect();
    const conversation = document.getElementById('conversationDetail');
    const conversationRect = conversation.getBoundingClientRect();
    return {
      isMini: document.documentElement.classList.contains('mini-mode'),
      miniConversation: document.documentElement.classList.contains('mini-conversation-expanded'),
      expanded: document.getElementById('capsule').getAttribute('aria-expanded'),
      conversationHidden: conversation.hidden,
      conversationOpen: conversation.classList.contains('open'),
      conversationWidth: conversationRect.width,
      messages: document.querySelectorAll('.conversation-message').length,
      pet: { left: pet.left, top: pet.top, width: pet.width, height: pet.height }
    };
  })()`, true);
  const expandedResizeRequest = window.visualResizeRequest;
  const petDrift = Math.max(
    Math.abs(expandedFromMini.pet.left - petBeforeConversation.left),
    Math.abs(expandedFromMini.pet.top - petBeforeConversation.top),
    Math.abs(expandedFromMini.pet.width - petBeforeConversation.width),
    Math.abs(expandedFromMini.pet.height - petBeforeConversation.height)
  );
  if (!expandedFromMini.isMini
      || !expandedFromMini.miniConversation
      || expandedFromMini.expanded !== 'false'
      || expandedFromMini.conversationHidden
      || !expandedFromMini.conversationOpen
      || Math.abs(expandedFromMini.conversationWidth - 342) > .5
      || expandedFromMini.messages !== 2
      || expandedResizeRequest?.mode !== "mini"
      || expandedResizeRequest?.conversationExpanded !== true
      || petDrift > .75) {
    throw new Error(`mini conversation did not keep the pet anchored: ${JSON.stringify({ ...expandedFromMini, expandedResizeRequest, petDrift })}`);
  }
  fs.writeFileSync(
    path.join(outputDirectory, "mini-pet-conversation-island@2x.png"),
    (await window.webContents.capturePage()).toPNG()
  );

  click(1, miniCenterX, miniCenterY);
  await wait(720);
  const collapsedConversation = await window.webContents.executeJavaScript(`({
    isMini: document.documentElement.classList.contains('mini-mode'),
    miniConversation: document.documentElement.classList.contains('mini-conversation-expanded'),
    conversationHidden: document.getElementById('conversationDetail').hidden
  })`, true);
  const collapsedResizeRequest = window.visualResizeRequest;
  if (!collapsedConversation.isMini
      || collapsedConversation.miniConversation
      || !collapsedConversation.conversationHidden
      || collapsedResizeRequest?.mode !== "mini"
      || collapsedResizeRequest?.conversationExpanded !== false) {
    throw new Error(`second mini single click did not retract conversation: ${JSON.stringify({ collapsedConversation, collapsedResizeRequest })}`);
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
  const rapidSweep = [
    { x: Math.round(base.left + 8), y: hoverY },
    { x: Math.round(base.left + base.width / 2), y: Math.round(base.top + base.height - 7) },
    { x: hoverX, y: hoverY },
    { x: Math.round(base.left + base.width / 2), y: Math.round(base.top + 7) }
  ];
  for (const point of rapidSweep) {
    window.webContents.sendInputEvent({ type: "mouseMove", x: point.x, y: point.y });
    await wait(12);
  }
  await wait(24);
  const rapidResult = await window.webContents.executeJavaScript(`(() => {
    const rect = document.getElementById("capsule").getBoundingClientRect();
    return { dx: rect.left - ${base.left}, dy: rect.top - ${base.top} };
  })()`, true);
  if (rapidResult.dy > -3.5 || Math.abs(rapidResult.dx) > 2.5) {
    throw new Error(`rapid magnetic sweep lagged behind the final pointer direction: ${JSON.stringify(rapidResult)}`);
  }
  window.webContents.sendInputEvent({ type: "mouseMove", x: hoverX, y: hoverY });
  await wait(48);
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
  if (process.argv.includes("--footstep-only")) {
    await assertFootstepImpactEffect();
    captureWindows.forEach((window) => { if (!window.isDestroyed()) window.destroy(); });
    app.quit();
    return;
  }
  if (process.argv.includes("--conversation-only")) {
    await assertTaskConversationIsland();
    await assertPointerDoubleClickMinimizes();
    captureWindows.forEach((window) => { if (!window.isDestroyed()) window.destroy(); });
    app.quit();
    return;
  }
  if (process.argv.includes("--orb-only")) {
    await assertOrbPet();
    captureWindows.forEach((window) => { if (!window.isDestroyed()) window.destroy(); });
    app.quit();
    return;
  }
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
  await assertAPIMiniStyleRules();
  await assertUpdateReminderInteraction();
  await assertPointerDoubleClickMinimizes();
  await assertLiveTokenRoll();
  await assertOfflineAPIMiniTime();
  await assertTaskConversationIsland();
  await assertMagnetAndDetailStayStable("clear");
  await assertMagnetAndDetailStayStable("off");
  for (const style of ["quota", "tokens", "status", "weather", "time"]) {
    await captureMini(style);
  }
  for (const pet of ["cat", "bunny", "ghost", "robot", "fox"]) {
    await captureMini("quota", null, null, null, pet);
    await captureMini("quota", "working", null, null, pet);
    await captureMini("quota", "attention", null, null, pet);
  }
  await assertOrbPet();
  await assertPetDesktopInteraction();
  await assertFootstepImpactEffect();
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
