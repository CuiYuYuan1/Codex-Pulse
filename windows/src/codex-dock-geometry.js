"use strict";

function finiteNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function normalizeTrackedWindowBounds(payload, screenAPI) {
  if (!payload || typeof payload !== "object") return null;
  const rawLeft = finiteNumber(payload.left ?? payload.x);
  const rawTop = finiteNumber(payload.top ?? payload.y);
  const rawRight = finiteNumber(
    payload.right ?? (rawLeft === null ? null : rawLeft + Number(payload.width))
  );
  const rawBottom = finiteNumber(
    payload.bottom ?? (rawTop === null ? null : rawTop + Number(payload.height))
  );
  if ([rawLeft, rawTop, rawRight, rawBottom].some((value) => value === null)) {
    return null;
  }

  let topLeft = { x: rawLeft, y: rawTop };
  let bottomRight = { x: rawRight, y: rawBottom };
  if (payload.physical === true && typeof screenAPI?.screenToDipPoint === "function") {
    try {
      topLeft = screenAPI.screenToDipPoint(topLeft);
      bottomRight = screenAPI.screenToDipPoint(bottomRight);
    } catch {
      return null;
    }
  }

  const left = Math.round(Math.min(topLeft.x, bottomRight.x));
  const top = Math.round(Math.min(topLeft.y, bottomRight.y));
  const right = Math.round(Math.max(topLeft.x, bottomRight.x));
  const bottom = Math.round(Math.max(topLeft.y, bottomRight.y));
  const width = right - left;
  const height = bottom - top;
  return width >= 420 && height >= 280
    ? { x: left, y: top, width, height }
    : null;
}

function visibleWindowBounds(windowBounds, shapeBounds, stableSurface = false) {
  if (!windowBounds) return null;
  if (!stableSurface || !shapeBounds) {
    return {
      x: Math.round(windowBounds.x),
      y: Math.round(windowBounds.y),
      width: Math.round(windowBounds.width),
      height: Math.round(windowBounds.height)
    };
  }
  return {
    x: Math.round(windowBounds.x + shapeBounds.x),
    y: Math.round(windowBounds.y + shapeBounds.y),
    width: Math.round(shapeBounds.width),
    height: Math.round(shapeBounds.height)
  };
}

function rectangleDistance(left, right) {
  const dx = Math.max(0, Math.max(
    left.x - (right.x + right.width),
    right.x - (left.x + left.width)
  ));
  const dy = Math.max(0, Math.max(
    left.y - (right.y + right.height),
    right.y - (left.y + left.height)
  ));
  return Math.hypot(dx, dy);
}

function isFullscreenWindowBounds(windowBounds, displayBounds, tolerance = 4) {
  if (!windowBounds || !displayBounds) return false;
  const inset = Math.max(0, finiteNumber(tolerance) ?? 4);
  return windowBounds.x <= displayBounds.x + inset
    && windowBounds.y <= displayBounds.y + inset
    && windowBounds.x + windowBounds.width
      >= displayBounds.x + displayBounds.width - inset
    && windowBounds.y + windowBounds.height
      >= displayBounds.y + displayBounds.height - inset;
}

function fullscreenTopDockFrame(
  windowBounds,
  {
    thickness = 44,
    overlap = 16,
    topInset = 24,
    widthRatio = 0.46,
    minimumWidth = 620,
    maximumWidth = 960,
    horizontalMargin = 24
  } = {}
) {
  if (!windowBounds) return null;
  const hostWidth = Math.max(1, Math.round(finiteNumber(windowBounds.width) ?? 1));
  const margin = Math.max(0, finiteNumber(horizontalMargin) ?? 24);
  const availableWidth = Math.max(420, hostWidth - margin * 2);
  const proportionalWidth = hostWidth
    * Math.max(0.1, finiteNumber(widthRatio) ?? 0.46);
  const width = Math.round(Math.min(
    availableWidth,
    Math.max(
      Math.max(420, finiteNumber(minimumWidth) ?? 620),
      Math.min(
        Math.max(420, finiteNumber(maximumWidth) ?? 960),
        proportionalWidth
      )
    )
  ));
  return {
    x: Math.round(windowBounds.x + (hostWidth - width) / 2),
    y: Math.round(windowBounds.y + Math.max(0, finiteNumber(topInset) ?? 24)),
    width,
    height: Math.round(
      Math.max(1, finiteNumber(thickness) ?? 44)
        + Math.max(0, finiteNumber(overlap) ?? 16)
    )
  };
}

function attachedDockShape(width, height, edge = "bottom", overlap = 16) {
  const resolvedWidth = Math.max(1, Math.round(finiteNumber(width) ?? 1));
  const resolvedHeight = Math.max(1, Math.round(finiteNumber(height) ?? 1));
  const inset = Math.max(
    0,
    Math.min(
      edge === "left" || edge === "right"
        ? resolvedWidth - 1
        : resolvedHeight - 1,
      Math.round(finiteNumber(overlap) ?? 0)
    )
  );

  if (edge === "top") {
    return { x: 0, y: 0, width: resolvedWidth, height: resolvedHeight - inset };
  }
  if (edge === "left") {
    return { x: 0, y: 0, width: resolvedWidth - inset, height: resolvedHeight };
  }
  if (edge === "right") {
    return { x: inset, y: 0, width: resolvedWidth - inset, height: resolvedHeight };
  }
  return { x: 0, y: inset, width: resolvedWidth, height: resolvedHeight - inset };
}

function mediaSourceIdForWindowHandle(value) {
  const raw = String(value ?? "").trim();
  if (!/^\d+$/.test(raw)) return null;
  try {
    const normalized = BigInt(raw);
    return normalized > 0n ? `window:${normalized}:0` : null;
  } catch {
    return null;
  }
}

function detachedWindowBounds(pointer, windowBounds, visibleShape) {
  const width = Math.max(1, Math.round(finiteNumber(windowBounds?.width) ?? 1));
  const height = Math.max(1, Math.round(finiteNumber(windowBounds?.height) ?? 1));
  const shapeX = finiteNumber(visibleShape?.x) ?? 0;
  const shapeY = finiteNumber(visibleShape?.y) ?? 0;
  const shapeWidth = Math.max(
    1,
    finiteNumber(visibleShape?.width) ?? width
  );
  const shapeHeight = Math.max(
    1,
    finiteNumber(visibleShape?.height) ?? height
  );
  const pointerX = finiteNumber(pointer?.x) ?? 0;
  const pointerY = finiteNumber(pointer?.y) ?? 0;
  return {
    x: Math.round(pointerX - shapeX - shapeWidth / 2),
    y: Math.round(pointerY - shapeY - shapeHeight / 2),
    width,
    height
  };
}

module.exports = {
  attachedDockShape,
  detachedWindowBounds,
  fullscreenTopDockFrame,
  isFullscreenWindowBounds,
  mediaSourceIdForWindowHandle,
  normalizeTrackedWindowBounds,
  visibleWindowBounds,
  rectangleDistance
};
