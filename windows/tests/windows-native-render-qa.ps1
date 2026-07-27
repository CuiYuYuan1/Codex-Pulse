param(
  [string]$Endpoint = "http://127.0.0.1:9223/json/list",
  [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  $OutputDirectory = Join-Path $projectRoot "output\windows-native-qa"
}

function Receive-CdpMessage {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket
  )

  $buffer = New-Object byte[] 1048576
  $stream = New-Object System.IO.MemoryStream
  do {
    $segment = [System.ArraySegment[byte]]::new($buffer)
    $result = $Socket.ReceiveAsync(
      $segment,
      [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()
    if ($result.Count -gt 0) {
      $stream.Write($buffer, 0, $result.Count)
    }
  } while (-not $result.EndOfMessage)

  $json = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
  $stream.Dispose()
  return $json | ConvertFrom-Json
}

$script:messageId = 0
function Invoke-Cdp {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$Method,
    [hashtable]$Parameters = @{}
  )

  $script:messageId += 1
  $requestId = $script:messageId
  $payload = @{
    id = $requestId
    method = $Method
    params = $Parameters
  } | ConvertTo-Json -Compress -Depth 20
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
  $segment = [System.ArraySegment[byte]]::new($bytes)
  $Socket.SendAsync(
    $segment,
    [System.Net.WebSockets.WebSocketMessageType]::Text,
    $true,
    [System.Threading.CancellationToken]::None
  ).GetAwaiter().GetResult()

  do {
    $message = Receive-CdpMessage -Socket $Socket
  } while ($null -eq $message.id -or [int]$message.id -ne $requestId)

  if ($null -ne $message.error) {
    throw "CDP $Method failed: $($message.error | ConvertTo-Json -Compress)"
  }
  return $message.result
}

function Invoke-JavaScript {
  param(
    [System.Net.WebSockets.ClientWebSocket]$Socket,
    [string]$Expression,
    [switch]$AwaitPromise
  )

  $result = Invoke-Cdp -Socket $Socket -Method "Runtime.evaluate" -Parameters @{
    expression = $Expression
    awaitPromise = $AwaitPromise.IsPresent
    returnByValue = $true
    userGesture = $true
  }
  if ($null -ne $result.exceptionDetails) {
    throw "JavaScript failed: $($result.exceptionDetails | ConvertTo-Json -Compress -Depth 10)"
  }
  return $result.result.value
}

$targets = Invoke-RestMethod -Uri $Endpoint
$target = $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
if ($null -eq $target) {
  throw "No renderer page was exposed by CodexPulse."
}

$socket = [System.Net.WebSockets.ClientWebSocket]::new()
$socket.ConnectAsync(
  [Uri]$target.webSocketDebuggerUrl,
  [System.Threading.CancellationToken]::None
).GetAwaiter().GetResult()

try {
  Invoke-Cdp -Socket $socket -Method "Runtime.enable" | Out-Null
  Invoke-Cdp -Socket $socket -Method "Page.enable" | Out-Null

  Invoke-JavaScript -Socket $socket -Expression @'
(() => {
  localStorage.setItem("codexPulse.petCharacter", "cat");
  if (!document.documentElement.classList.contains("mini-mode")) {
    document.getElementById("capsule").dispatchEvent(
      new MouseEvent("dblclick", { button: 0, bubbles: true })
    );
  }
  return true;
})()
'@ | Out-Null
  Start-Sleep -Milliseconds 950

  $topEdgeRoam = Invoke-JavaScript -Socket $socket -AwaitPromise -Expression @'
(async () => {
  cancelPetRoam();
  clearTimeout(petRoamTimer);
  petRoamTimer = null;
  petRoamInFlight = true;
  const settle = await window.pulse.runPetRoam({
    x: window.screenX,
    y: 0,
    duration: 1.5,
    arcHeight: 0
  });
  const arced = await window.pulse.runPetRoam({
    x: window.screenX + 120,
    y: 0,
    duration: 1.5,
    arcHeight: 7
  });
  return { settle, arced, screenX: window.screenX, screenY: window.screenY };
})()
'@

  $baseline = Invoke-JavaScript -Socket $socket -Expression @'
(() => {
  cancelPetRoam();
  petCharacterPreference = "cat";
  elements.capsule.dataset.pet = "cat";
  proceduralCat.setCharacter("cat");
  petRoamingState = "idle";
  proceduralCat.setFacesLeft(false);
  proceduralCat.setState("idle");
  const canvas = document.getElementById("petCatCanvas");
  const rect = canvas.getBoundingClientRect();
  return {
    miniMode: document.documentElement.classList.contains("mini-mode"),
    backingWidth: canvas.width,
    backingHeight: canvas.height,
    cssWidth: rect.width,
    cssHeight: rect.height,
    backingAspect: canvas.width / canvas.height,
    cssAspect: rect.width / rect.height,
    state: canvas.dataset.state || ""
  };
})()
'@
  Start-Sleep -Milliseconds 450

  $baselinePixels = Invoke-JavaScript -Socket $socket -Expression @'
(() => {
  const canvas = document.getElementById("petCatCanvas");
  const pixels = canvas.getContext("2d").getImageData(0, 222, 30, 55).data;
  return Array.from(pixels)
    .filter((_, index) => index % 4 === 3 && pixels[index] > 8).length;
})()
'@

  Invoke-JavaScript -Socket $socket -Expression @'
(() => {
  petRoamingState = "walk_right";
  proceduralCat.setFacesLeft(false);
  proceduralCat.setState("walk_right");
  return true;
})()
'@ | Out-Null
  Start-Sleep -Milliseconds 650

  $impact = Invoke-JavaScript -Socket $socket -Expression @'
(() => {
  const canvas = document.getElementById("petCatCanvas");
  const pixels = canvas.getContext("2d").getImageData(0, 222, 30, 55).data;
  return {
    state: canvas.dataset.state || "",
    visiblePixels: Array.from(pixels)
      .filter((_, index) => index % 4 === 3 && pixels[index] > 8).length
  };
})()
'@

  $frameStats = Invoke-JavaScript -Socket $socket -AwaitPromise -Expression @'
new Promise((resolve) => {
  const samples = [];
  let previous = performance.now();
  const tick = (now) => {
    samples.push(now - previous);
    previous = now;
    if (samples.length < 180) {
      requestAnimationFrame(tick);
      return;
    }
    const sorted = samples.slice(12).sort((left, right) => left - right);
    resolve({
      frameCount: samples.length,
      average: sorted.reduce((sum, value) => sum + value, 0) / sorted.length,
      p95: sorted[Math.floor(sorted.length * .95)] || 0,
      p99: sorted[Math.floor(sorted.length * .99)] || 0,
      max: sorted[sorted.length - 1] || 0
    });
  };
  requestAnimationFrame(tick);
})
'@

  $transitionStats = Invoke-JavaScript -Socket $socket -AwaitPromise -Expression @'
new Promise((resolve) => {
  const states = ["thinking", "waiting_auth", "idle", "walk_left", "walk_right"];
  const samples = [];
  const observedStates = new Set();
  let previous = performance.now();
  let stateIndex = 0;
  const changeState = () => {
    const state = states[stateIndex];
    petRoamingState = state;
    proceduralCat.setFacesLeft(state === "walk_left");
    proceduralCat.setState(state);
    stateIndex += 1;
    if (stateIndex < states.length) setTimeout(changeState, 650);
  };
  changeState();
  const tick = (now) => {
    samples.push(now - previous);
    previous = now;
    observedStates.add(document.getElementById("petCatCanvas").dataset.state || "");
    if (stateIndex < states.length || samples.length < 220) {
      requestAnimationFrame(tick);
      return;
    }
    const sorted = samples.slice(12).sort((left, right) => left - right);
    resolve({
      frameCount: samples.length,
      p95: sorted[Math.floor(sorted.length * .95)] || 0,
      p99: sorted[Math.floor(sorted.length * .99)] || 0,
      max: sorted[sorted.length - 1] || 0,
      observedStates: Array.from(observedStates)
    });
  };
  requestAnimationFrame(tick);
})
'@

  New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
  $characterResults = [ordered]@{}
  foreach ($character in @("cat", "dino", "bunny", "ghost", "robot", "fox")) {
    Invoke-JavaScript -Socket $socket -Expression @"
(() => {
  petCharacterPreference = "$character";
  elements.capsule.dataset.pet = "$character";
  petRoamingState = "walk_right";
  proceduralCat.setCharacter("$character");
  proceduralCat.setFacesLeft(false);
  proceduralCat.setState("walk_right");
  return true;
})()
"@ | Out-Null
    Start-Sleep -Milliseconds 650

    $characterStats = Invoke-JavaScript -Socket $socket -AwaitPromise -Expression @'
new Promise((resolve) => {
  const samples = [];
  let previous = performance.now();
  const tick = (now) => {
    samples.push(now - previous);
    previous = now;
    if (samples.length < 90) {
      requestAnimationFrame(tick);
      return;
    }
    const canvas = document.getElementById("petCatCanvas");
    const pixels = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height).data;
    let minX = canvas.width;
    let minY = canvas.height;
    let maxX = -1;
    let maxY = -1;
    let visiblePixels = 0;
    for (let y = 0; y < canvas.height; y += 1) {
      for (let x = 0; x < canvas.width; x += 1) {
        if (pixels[(y * canvas.width + x) * 4 + 3] <= 8) continue;
        visiblePixels += 1;
        minX = Math.min(minX, x);
        minY = Math.min(minY, y);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
      }
    }
    const sorted = samples.slice(8).sort((left, right) => left - right);
    resolve({
      state: canvas.dataset.state || "",
      frameCount: samples.length,
      p95: sorted[Math.floor(sorted.length * .95)] || 0,
      p99: sorted[Math.floor(sorted.length * .99)] || 0,
      max: sorted[sorted.length - 1] || 0,
      visiblePixels,
      alphaBounds: { minX, minY, maxX, maxY },
      touchesCanvasEdge: minX <= 0 || minY <= 0
        || maxX >= canvas.width - 1 || maxY >= canvas.height - 1
    });
  };
  requestAnimationFrame(tick);
})
'@
    $characterResults[$character] = $characterStats

    $characterScreenshot = Invoke-Cdp -Socket $socket -Method "Page.captureScreenshot" -Parameters @{
      format = "png"
      fromSurface = $true
      captureBeyondViewport = $false
    }
    [System.IO.File]::WriteAllBytes(
      (Join-Path $OutputDirectory "windows-native-$character-walk.png"),
      [Convert]::FromBase64String($characterScreenshot.data)
    )
  }

  $result = [ordered]@{
    platform = "Windows"
    userAgent = Invoke-JavaScript -Socket $socket -Expression "navigator.userAgent"
    topEdgeRoam = $topEdgeRoam
    geometry = $baseline
    baselinePixels = $baselinePixels
    impact = $impact
    impactPixelGain = [int]$impact.visiblePixels - [int]$baselinePixels
    steadyWalkFrames = $frameStats
    stateTransitionFrames = $transitionStats
    characters = $characterResults
    screenshotDirectory = $OutputDirectory
  }
  $result | ConvertTo-Json -Depth 10
} finally {
  if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    $socket.CloseAsync(
      [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
      "QA complete",
      [System.Threading.CancellationToken]::None
    ).GetAwaiter().GetResult()
  }
  $socket.Dispose()
}
