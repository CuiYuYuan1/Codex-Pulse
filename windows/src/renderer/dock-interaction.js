(function exposeCodexDockInteraction(globalScope) {
  "use strict";

  const DETACH_DISTANCE = 18;

  function isVertical(edge) {
    return edge === "left" || edge === "right";
  }

  // Positive values point away from Codex; negative values point into it.
  // Both directions are valid detachment gestures.
  function normalDistance(edge, dx, dy) {
    if (edge === "top") return -Number(dy || 0);
    if (edge === "left") return -Number(dx || 0);
    if (edge === "right") return Number(dx || 0);
    return Number(dy || 0);
  }

  function detachDirection(edge, dx, dy) {
    return normalDistance(edge, dx, dy) < 0 ? -1 : 1;
  }

  function detachmentOffset(edge, direction, distance) {
    const signed = (Number(direction) < 0 ? -1 : 1) * Math.max(0, Number(distance) || 0);
    if (edge === "top") return { x: 0, y: -signed };
    if (edge === "left") return { x: -signed, y: 0 };
    if (edge === "right") return { x: signed, y: 0 };
    return { x: 0, y: signed };
  }

  function dragAxis(edge, dx, dy) {
    const horizontal = Math.abs(Number(dx || 0));
    const vertical = Math.abs(Number(dy || 0));
    if (Math.hypot(horizontal, vertical) < 3) return null;
    const perpendicular = isVertical(edge) ? horizontal : vertical;
    const parallel = isVertical(edge) ? vertical : horizontal;
    if (Math.abs(normalDistance(edge, dx, dy)) >= 3 && perpendicular > parallel * 1.05) {
      return "detach";
    }
    return parallel > perpendicular * 1.05 ? "reorder" : null;
  }

  function detachProgress(edge, dx, dy) {
    return Math.max(
      0,
      Math.min(1, Math.abs(normalDistance(edge, dx, dy)) / DETACH_DISTANCE)
    );
  }

  const api = Object.freeze({
    DETACH_DISTANCE,
    detachDirection,
    detachProgress,
    detachmentOffset,
    dragAxis,
    isVertical,
    normalDistance
  });

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  globalScope.CodexDockInteraction = api;
})(typeof globalThis === "undefined" ? window : globalThis);
