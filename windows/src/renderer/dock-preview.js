const edge = new URLSearchParams(window.location.search).get("edge");
document.documentElement.dataset.edge = ["top", "bottom", "left", "right"].includes(edge)
  ? edge
  : "bottom";
