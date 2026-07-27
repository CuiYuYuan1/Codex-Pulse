// Event Horizon pet renderer.
// Adapted from tiyda/blackhole-desktop and s0xDk/ghostty-blackhole (MIT).
// See ../../THIRD_PARTY_NOTICES.md in the source distribution.
(() => {
  "use strict";

  const vertexSource = `#version 300 es
    in vec2 aPosition;
    out vec2 vUV;
    void main() {
      gl_Position = vec4(aPosition, 0.0, 1.0);
      vUV = vec2(aPosition.x * 0.5 + 0.5, 0.5 - aPosition.y * 0.5);
    }
  `;

  const fragmentSource = `#version 300 es
    precision highp float;
    precision highp int;

    in vec2 vUV;
    out vec4 outColor;

    uniform sampler2D uDesktop;
    uniform vec2 uResolution;
    uniform vec2 uCaptureOrigin;
    uniform vec2 uCaptureSize;
    uniform float uTime;
    uniform float uCaptureReady;

    const float DISK_TEMP = 5500.0;
    const float DISK_INCL = 1.50;
    const float DISK_ROLL = 0.35;
    const float DISK_INNER = 1.8;
    const float DISK_OUTER = 8.0;
    const float DISK_OPACITY = 0.90;
    const float DOPPLER_MIX = 0.60;
    const float DISK_BEAM = 2.5;
    const float DISK_GAIN = 2.2;
    const float DISK_CONTRAST = 1.6;
    const float DISK_WIND = 7.0;
    const float DISK_SPEED = 5.0;
    const float EXPOSURE = 1.40;
    const float STAR_GAIN = 0.0;

    struct DiskLook {
      float temp;
      float incl;
      float roll;
      float inner;
      float outer;
      float opacity;
      float doppler;
      float beam;
      float gain;
      float contrast;
      float wind;
      float speed;
      float exposure;
      float star;
    };

    DiskLook diskLookAt(int index) {
      switch (index) {
        case 1: return DiskLook(4500.0, 1.52, 0.10, 2.2, 7.0, 0.85, 0.35, 2.0, 1.4, 0.5, 7.0, 5.0, 1.20, 0.0);
        case 2: return DiskLook(3800.0, 0.55, -0.30, 2.2, 6.0, 0.45, 0.90, 3.5, 1.6, 0.4, 3.0, 2.5, 1.10, 0.0);
        case 3: return DiskLook(6500.0, 0.30, 0.00, 3.0, 10.0, 0.50, 0.80, 2.5, 1.0, 1.1, 7.0, 5.0, 1.00, 0.0);
        case 4: return DiskLook(15000.0, 1.30, 0.35, 3.0, 14.0, 0.35, 1.00, 4.0, 1.2, 1.3, 8.0, 5.0, 0.80, 0.0);
        case 5: return DiskLook(18000.0, 1.05, 0.55, 3.0, 16.0, 0.30, 1.00, 5.0, 1.0, 1.5, 9.0, 6.0, 0.75, 0.0);
        case 6: return DiskLook(5500.0, 1.50, 0.35, 1.8, 8.0, 0.00, 1.00, 2.5, 0.0, 1.6, 7.0, 5.0, 1.00, 0.6);
        default: return DiskLook(
          DISK_TEMP, DISK_INCL, DISK_ROLL, DISK_INNER, DISK_OUTER,
          DISK_OPACITY, DOPPLER_MIX, DISK_BEAM, DISK_GAIN,
          DISK_CONTRAST, DISK_WIND, DISK_SPEED, EXPOSURE, STAR_GAIN
        );
      }
    }

    DiskLook mixDiskLook(DiskLook a, DiskLook b, float amount) {
      return DiskLook(
        mix(a.temp, b.temp, amount),
        mix(a.incl, b.incl, amount),
        mix(a.roll, b.roll, amount),
        mix(a.inner, b.inner, amount),
        mix(a.outer, b.outer, amount),
        mix(a.opacity, b.opacity, amount),
        mix(a.doppler, b.doppler, amount),
        mix(a.beam, b.beam, amount),
        mix(a.gain, b.gain, amount),
        mix(a.contrast, b.contrast, amount),
        mix(a.wind, b.wind, amount),
        mix(a.speed, b.speed, amount),
        mix(a.exposure, b.exposure, amount),
        mix(a.star, b.star, amount)
      );
    }

    DiskLook demoDiskLook(float time) {
      float slotClock = mod(time, 42.0) / 42.0 * 8.0;
      int index = min(int(floor(slotClock)), 7);
      int nextIndex = (index + 1) % 8;
      float blend = smoothstep(0.82, 1.0, fract(slotClock));
      return mixDiskLook(
        diskLookAt(index),
        diskLookAt(nextIndex),
        blend
      );
    }

    vec2 mirrorUV(vec2 value) {
      return 1.0 - abs(1.0 - mod(value, 2.0));
    }

    vec2 rotate2D(vec2 point, float angle) {
      float c = cos(angle);
      float s = sin(angle);
      return vec2(c * point.x - s * point.y, s * point.x + c * point.y);
    }

    float hash21(vec2 point) {
      point = fract(point * vec2(234.34, 435.345));
      point += dot(point, point + 34.23);
      return fract(point.x * point.y);
    }

    float noise21(vec2 point) {
      vec2 index = floor(point);
      vec2 fraction = fract(point);
      fraction = fraction * fraction * (3.0 - 2.0 * fraction);
      return mix(
        mix(hash21(index), hash21(index + vec2(1.0, 0.0)), fraction.x),
        mix(hash21(index + vec2(0.0, 1.0)), hash21(index + 1.0), fraction.x),
        fraction.y
      );
    }

    float noiseWrapY(vec2 point, float periodY) {
      vec2 index = floor(point);
      vec2 fraction = fract(point);
      fraction = fraction * fraction * (3.0 - 2.0 * fraction);
      float y0 = mod(index.y, periodY);
      float y1 = mod(index.y + 1.0, periodY);
      return mix(
        mix(
          hash21(vec2(index.x, y0)),
          hash21(vec2(index.x + 1.0, y0)),
          fraction.x
        ),
        mix(
          hash21(vec2(index.x, y1)),
          hash21(vec2(index.x + 1.0, y1)),
          fraction.x
        ),
        fraction.y
      );
    }

    vec3 blackbody(float temperature) {
      float t = clamp(temperature, 1500.0, 40000.0) / 100.0;
      float r = t <= 66.0
        ? 1.0
        : clamp(1.292936 * pow(t - 60.0, -0.1332047), 0.0, 1.0);
      float g = t <= 66.0
        ? clamp(0.3900816 * log(t) - 0.6318414, 0.0, 1.0)
        : clamp(1.1298909 * pow(t - 60.0, -0.0755148), 0.0, 1.0);
      float b = t >= 66.0
        ? 1.0
        : (t <= 19.0 ? 0.0 : clamp(0.5432068 * log(t - 10.0) - 1.196254, 0.0, 1.0));
      return vec3(r, g, b);
    }

    vec3 sampleDesktop(vec2 localUV) {
      if (uCaptureReady < 0.5 || uCaptureSize.x <= 0.0 || uCaptureSize.y <= 0.0) {
        return vec3(0.006, 0.008, 0.014);
      }
      vec2 captureUV = uCaptureOrigin + clamp(localUV, 0.0, 1.0) * uCaptureSize;
      return texture(uDesktop, clamp(captureUV, 0.0, 1.0)).rgb;
    }

    void main() {
      vec2 uv = vUV;
      float aspect = uResolution.x / max(uResolution.y, 1.0);
      float time = uTime;
      bool captureReady = uCaptureReady >= 0.5
        && uCaptureSize.x > 0.0
        && uCaptureSize.y > 0.0;
      DiskLook look = demoDiskLook(time);
      // Shape and color may tour; Token growth owns the only geometry scale.
      look.outer = 8.0;
      float breathing = 1.0
        + 0.055 * sin(time * 1.25)
        + 0.020 * sin(time * 0.53 + 1.2);
      float intensity = 1.0;
      // Keep the physical hole size tied to scene width. The taller
      // black-hole canvas adds vertical room without becoming a size control.
      float holeRadius = aspect * 0.0926;
      float dynamicRoll = look.roll + 0.12 * sin(time * 0.31);
      float maskExtent = max(4.2, look.outer / 2.5980762 + 0.8);
      // The native pet window roams across the desktop. The shader stays
      // aligned with the code/file infall target inside that moving window.
      vec2 center = vec2(0.48, 0.53);
      vec2 point = (uv - center) * vec2(aspect, 1.0);
      float pointLength = length(point);
      float lensWindow = exp(-pow(pointLength / (7.0 * holeRadius), 2.0));
      float mask = 1.0 - smoothstep(
        (maskExtent - 0.7) * holeRadius,
        maskExtent * holeRadius,
        pointLength
      );
      if (mask < 0.002) {
        outColor = vec4(0.0);
        return;
      }

      const float criticalImpact = 2.5980762;
      const float startingDepth = 14.0;
      float rayScale = criticalImpact / max(holeRadius, 0.0001);
      vec2 projectedRay = rotate2D(vec2(point.x, -point.y), dynamicRoll) * rayScale;
      float impact = length(projectedRay);

      if (impact > look.outer + 3.0) {
        if (!captureReady) {
          outColor = vec4(0.0);
          return;
        }
        float deflection = (2.0 / (rayScale * rayScale))
          / max(pointLength, 0.0001)
          * (13.0 / lensWindow * lensWindow)
          * lensWindow;
        vec2 sampledUV = mirrorUV(
          center + (point - normalize(point) * deflection) / vec2(aspect, 1.0)
        );
        vec3 color = sampleDesktop(sampledUV);
        // The Windows transparent BrowserWindow compositor expects
        // premultiplied WebGL output. Straight RGB at a tiny edge alpha is
        // interpreted as a bright opaque fringe by DirectComposition.
        outColor = vec4(color * mask, mask);
        return;
      }

      vec3 position = vec3(projectedRay, startingDepth);
      vec3 velocity = vec3(0.0, 0.0, -1.0);
      vec3 previous = position;
      float angularMomentumSquared = dot(projectedRay, projectedRay);
      vec3 diskNormal = vec3(0.0, sin(look.incl), cos(look.incl));
      float previousPlane = dot(position, diskNormal);
      vec3 emission = vec3(0.0);
      float transmittance = 1.0;
      bool captured = false;

      for (int step = 0; step < 48; step++) {
        float radiusSquared = dot(position, position);
        if (radiusSquared < 1.0) {
          captured = true;
          break;
        }
        if (position.z < -startingDepth && velocity.z < 0.0) break;

        float physicalRadius = sqrt(radiusSquared);
        float delta = clamp(0.16 * physicalRadius, 0.03, 1.5);
        vec3 acceleration = -1.5 * angularMomentumSquared * position
          / (radiusSquared * radiusSquared * physicalRadius);
        velocity += acceleration * 0.5 * delta;
        position += velocity * delta;

        radiusSquared = dot(position, position);
        physicalRadius = sqrt(radiusSquared);
        acceleration = -1.5 * angularMomentumSquared * position
          / (radiusSquared * radiusSquared * physicalRadius);
        velocity += acceleration * 0.5 * delta;

        float plane = dot(position, diskNormal);
        if (plane * previousPlane < 0.0 && transmittance > 0.02) {
          float interpolation = previousPlane / (previousPlane - plane);
          vec3 hit = mix(previous, position, interpolation);
          float crossingRadius = length(hit);
          if (crossingRadius > look.inner && crossingRadius < look.outer) {
            float angle = atan(
              dot(hit, vec3(0.0, cos(look.incl), -sin(look.incl))),
              hit.x
            );
            float turns = angle / 6.2831853;
            float localDilation = sqrt(max(1.0 - 1.5 / crossingRadius, 0.02));
            float kepler = pow(look.inner / crossingRadius, 1.5);
            float speedDirection = look.speed < 0.0 ? -1.0 : 1.0;
            float dilation = mix(1.0, 0.20, intensity);
            float swirl = crossingRadius * look.wind * 0.12
              - time
                * kepler
                * abs(look.speed)
                * localDilation
                * dilation
                * speedDirection;
            float streak = noiseWrapY(vec2(
              crossingRadius * 2.8,
              turns * 19.0 + swirl * 3.0
            ), 19.0) * 0.65 + noiseWrapY(vec2(
              crossingRadius,
              turns * 9.0 + swirl * 1.5 + 7.0
            ), 9.0) * 0.35;
            streak = 0.35 + look.contrast * streak * streak;
            float band = smoothstep(
              look.inner,
              look.inner * 1.25,
              crossingRadius
            ) * (1.0 - smoothstep(
              look.outer * 0.70,
              look.outer,
              crossingRadius
            ));
            float beta = clamp(inversesqrt(max(2.0 * (crossingRadius - 1.0), 0.2)), 0.0, 0.99);
            float gPhysics = localDilation
              / max(1.0 + beta * dot(
                normalize(cross(diskNormal, hit)) * speedDirection,
                normalize(velocity)
              ), 0.05);
            float redshift = mix(1.0, gPhysics, look.doppler);
            float temperature = pow(look.inner / crossingRadius, 0.75)
              * pow(max(1.0 - sqrt(look.inner / crossingRadius), 0.0), 0.25)
              / 0.488;
            float density = band * streak;
            emission += transmittance
              * blackbody(look.temp * temperature * redshift)
              * (2.2 * look.gain * density * temperature * temperature * pow(redshift, look.beam));
            transmittance *= 1.0 - clamp(look.opacity * density, 0.0, 1.0);
          }
        }
        previousPlane = plane;
        previous = position;
      }

      if (!captured && dot(position, position) < 4.0) captured = true;

      vec3 background = vec3(0.0);
      if (!captured) {
        vec3 direction = normalize(velocity);
        if (direction.z < -0.05) {
          float distance = (-13.0 - position.z) / direction.z;
          vec2 sky = rotate2D((position + direction * distance).xy, -dynamicRoll) / rayScale;
          vec2 sampledUV = mirrorUV(
            center + (point + (vec2(sky.x, -sky.y) - point) * lensWindow) / vec2(aspect, 1.0)
          );
          background = sampleDesktop(sampledUV);
          if (look.star > 0.0) {
            float star = pow(
              hash21(floor(sampledUV * uResolution / 5.0)),
              32.0
            ) * look.star;
            background += vec3(0.55, 0.72, 1.0) * star;
          }
        }
      }

      float brightnessPulse = mix(
        0.72,
        1.25,
        0.5 + 0.5 * sin(time * 0.74 + 0.6)
      ) * breathing;
      vec3 visibleEmission = (1.0 - exp(-emission * look.exposure))
        * brightnessPulse;
      vec3 color = background * transmittance + visibleEmission;
      float emissionAlpha = clamp(
        max(visibleEmission.r, max(visibleEmission.g, visibleEmission.b)) * 1.35,
        0.0,
        1.0
      );
      float fallbackAlpha = captured ? 1.0 : emissionAlpha;
      float outputAlpha = captureReady ? mask : min(mask, fallbackAlpha);
      outColor = vec4(color * outputAlpha, outputAlpha);
    }
  `;

  const classicCodeGlyphs = Object.freeze(Array.from(
    "constanswer=42;absorb(token);returninsight;"
  ));

  function fragmentRandom(seed, salt) {
    const value = Math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
    return value - Math.floor(value);
  }

  function createShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const message = gl.getShaderInfoLog(shader) || "unknown shader error";
      gl.deleteShader(shader);
      throw new Error(message);
    }
    return shader;
  }

  function createProgram(gl) {
    const program = gl.createProgram();
    const vertex = createShader(gl, gl.VERTEX_SHADER, vertexSource);
    const fragment = createShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
    gl.attachShader(program, vertex);
    gl.attachShader(program, fragment);
    gl.linkProgram(program);
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(program) || "black-hole program link failed");
    }
    return program;
  }

  class BlackHolePetRenderer {
    constructor(canvas, codeLayer, options = {}) {
      this.canvas = canvas;
      this.codeLayer = codeLayer;
      this.reduceMotion = options.reduceMotion === true;
      this.gl = canvas.getContext("webgl2", {
        alpha: true,
        antialias: false,
        premultipliedAlpha: true,
        powerPreference: "high-performance"
      });
      this.active = false;
      this.state = "idle";
      this.dropState = "idle";
      this.captureStream = null;
      this.captureGeometry = null;
      this.captureDisplayId = null;
      this.captureRestartTimer = null;
      this.frame = null;
      this.startedAt = performance.now();
      this.lastGeometryAt = 0;
      this.video = document.createElement("video");
      this.video.muted = true;
      this.video.playsInline = true;
      this.video.autoplay = true;
      this.video.disablePictureInPicture = true;
      this.geometryRevision = 0;
      this.removeGeometryListener = typeof window.pulse?.onBlackHoleCaptureGeometry === "function"
        ? window.pulse.onBlackHoleCaptureGeometry((geometry) => {
          this.geometryRevision += 1;
          this.applyCaptureGeometry(geometry);
        })
        : null;

      if (!this.gl) return;
      const gl = this.gl;
      try {
        this.program = createProgram(gl);
      } catch (error) {
        console.error("Event Horizon WebGL shader failed", error);
        this.program = null;
        return;
      }
      this.locations = Object.fromEntries([
        "uResolution", "uCaptureOrigin", "uCaptureSize", "uTime",
        "uCaptureReady", "uDesktop"
      ].map((name) => [name, gl.getUniformLocation(this.program, name)]));
      const position = gl.getAttribLocation(this.program, "aPosition");
      const buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
        gl.STATIC_DRAW
      );
      this.vertexArray = gl.createVertexArray();
      gl.bindVertexArray(this.vertexArray);
      gl.enableVertexAttribArray(position);
      gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
      this.texture = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, this.texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA,
        1,
        1,
        0,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        new Uint8Array([1, 2, 4, 255])
      );
      this.installCodeGlyphs();
    }

    installCodeGlyphs() {
      if (!this.codeLayer) return;
      const intervalSeconds = this.reduceMotion ? 0.72 : 0.36;
      const cycleSeconds = classicCodeGlyphs.length * intervalSeconds;
      this.codeLayer.replaceChildren(...classicCodeGlyphs.map((glyph, index) => {
        const code = document.createElement("code");
        const angle = fragmentRandom(index, 1) * Math.PI * 2;
        const radius = 82 + fragmentRandom(index, 2) * 30;
        const curve = (
          fragmentRandom(index, 3) - 0.5
        ) * (this.reduceMotion ? 8 : 22);
        const spawnX = Math.cos(angle) * radius;
        const spawnY = Math.sin(angle) * radius * 0.62;
        const tangentX = -Math.sin(angle) * curve;
        const tangentY = Math.cos(angle) * curve * 0.62;
        const middleX = spawnX * 0.48 + tangentX;
        const middleY = spawnY * 0.48 + tangentY;
        const turn = (
          fragmentRandom(index, 4) - 0.5
        ) * (this.reduceMotion ? 10 : 28);

        code.setAttribute("aria-hidden", "true");
        code.textContent = glyph;
        code.classList.toggle("is-warm", index % 3 !== 0);
        code.style.setProperty("--spawn-x", `${spawnX.toFixed(2)}px`);
        code.style.setProperty("--spawn-y", `${spawnY.toFixed(2)}px`);
        code.style.setProperty("--middle-x", `${middleX.toFixed(2)}px`);
        code.style.setProperty("--middle-y", `${middleY.toFixed(2)}px`);
        code.style.setProperty("--near-x", `${(spawnX * 0.13).toFixed(2)}px`);
        code.style.setProperty("--near-y", `${(spawnY * 0.13).toFixed(2)}px`);
        code.style.setProperty("--middle-turn", `${(turn * 0.55).toFixed(2)}deg`);
        code.style.setProperty("--turn", `${turn.toFixed(2)}deg`);
        code.style.setProperty("--delay", `${(index * intervalSeconds).toFixed(2)}s`);
        code.style.setProperty("--cycle", `${cycleSeconds.toFixed(2)}s`);
        return code;
      }));
    }

    async setActive(active) {
      const next = active === true;
      if (this.active === next) return;
      this.active = next;
      if (!next) {
        this.stopCapture();
        if (typeof window.pulse?.setBlackHoleCaptureMode === "function") {
          await window.pulse.setBlackHoleCaptureMode(false);
        }
        cancelAnimationFrame(this.frame);
        this.frame = null;
        this.clear();
        return;
      }
      if (typeof window.pulse?.setBlackHoleCaptureMode === "function") {
        await window.pulse.setBlackHoleCaptureMode(true);
      }
      this.startedAt = performance.now();
      await this.startCapture();
      this.render();
    }

    setState(state) {
      this.state = String(state || "idle");
      const thinking = this.state === "thinking" || this.state === "running" || this.state === "working";
      this.codeLayer?.classList.toggle("is-thinking", thinking);
    }

    setDropState(state) {
      this.dropState = String(state || "idle");
    }

    async resetAfterSystemResume() {
      this.startedAt = performance.now();
      this.lastGeometryAt = 0;
      this.captureGeometry = null;
      this.captureDisplayId = null;
      this.stopCapture();
      this.clear();
      if (!this.active) return;
      if (typeof window.pulse?.setBlackHoleCaptureMode === "function") {
        await window.pulse.setBlackHoleCaptureMode(true);
      }
      await this.startCapture();
    }

    async startCapture() {
      if (!this.active || this.captureStream || !navigator.mediaDevices?.getDisplayMedia) return;
      try {
        this.applyCaptureGeometry(
          await window.pulse?.getBlackHoleCaptureGeometry?.(),
          { restartOnDisplayChange: false }
        );
        const stream = await navigator.mediaDevices.getDisplayMedia({
          audio: false,
          video: {
            frameRate: {
              ideal: this.reduceMotion ? 24 : 60,
              max: this.reduceMotion ? 30 : 60
            },
            width: { ideal: 3840 },
            height: { ideal: 2160 }
          }
        });
        if (!this.active) {
          for (const track of stream.getTracks()) track.stop();
          return;
        }
        this.captureStream = stream;
        this.video.srcObject = stream;
        await this.video.play();
        const track = stream.getVideoTracks()[0];
        if (track && "contentHint" in track) track.contentHint = "motion";
        track?.addEventListener("ended", () => {
          this.captureStream = null;
          if (this.active) this.scheduleCaptureRestart();
        }, { once: true });
      } catch (error) {
        console.warn("Event Horizon capture unavailable; using local fallback", error);
        this.captureStream = null;
      }
    }

    stopCapture() {
      clearTimeout(this.captureRestartTimer);
      this.captureRestartTimer = null;
      if (this.captureStream) {
        for (const track of this.captureStream.getTracks()) track.stop();
      }
      this.captureStream = null;
      this.video.srcObject = null;
    }

    scheduleCaptureRestart() {
      clearTimeout(this.captureRestartTimer);
      this.captureRestartTimer = setTimeout(() => {
        this.captureRestartTimer = null;
        if (this.active) void this.startCapture();
      }, 80);
    }

    async refreshGeometry(now) {
      if (now - this.lastGeometryAt < 1000) return;
      this.lastGeometryAt = now;
      const requestedAtRevision = this.geometryRevision;
      const geometry = await window.pulse?.getBlackHoleCaptureGeometry?.();
      // A pushed move event is newer than this fallback IPC response.
      if (requestedAtRevision !== this.geometryRevision) return;
      this.applyCaptureGeometry(geometry);
    }

    applyCaptureGeometry(geometry, { restartOnDisplayChange = true } = {}) {
      if (!geometry) return;
      const nextDisplay = String(geometry.displayId ?? "");
      const changedDisplay = this.captureDisplayId
        && nextDisplay
        && nextDisplay !== this.captureDisplayId;
      this.captureGeometry = geometry;
      if (nextDisplay) this.captureDisplayId = nextDisplay;
      if (changedDisplay && restartOnDisplayChange) {
        this.stopCapture();
        this.scheduleCaptureRestart();
      }
    }

    captureRect() {
      const geometry = this.captureGeometry;
      const windowBounds = geometry?.windowBounds;
      const displayBounds = geometry?.displayBounds;
      if (!windowBounds || !displayBounds || displayBounds.width <= 0 || displayBounds.height <= 0) {
        return { x: 0, y: 0, width: 0, height: 0 };
      }
      const canvasRect = this.canvas.getBoundingClientRect();
      return {
        x: (windowBounds.x + canvasRect.left - displayBounds.x) / displayBounds.width,
        y: (windowBounds.y + canvasRect.top - displayBounds.y) / displayBounds.height,
        width: canvasRect.width / displayBounds.width,
        height: canvasRect.height / displayBounds.height
      };
    }

    clear() {
      if (!this.gl) return;
      this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      this.gl.clearColor(0, 0, 0, 0);
      this.gl.clear(this.gl.COLOR_BUFFER_BIT);
    }

    render = (now = performance.now()) => {
      if (!this.active || !this.gl || !this.program) {
        this.frame = null;
        return;
      }
      void this.refreshGeometry(now);
      const gl = this.gl;
      const pixelRatio = Math.min(2, window.devicePixelRatio || 1);
      const displayRect = this.canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(displayRect.width * pixelRatio));
      const height = Math.max(1, Math.round(displayRect.height * pixelRatio));
      if (this.canvas.width !== width || this.canvas.height !== height) {
        this.canvas.width = width;
        this.canvas.height = height;
      }
      gl.viewport(0, 0, width, height);
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.useProgram(this.program);
      gl.bindVertexArray(this.vertexArray);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.texture);
      const captureReady = this.video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA;
      if (captureReady) {
        try {
          gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
          gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            this.video
          );
        } catch {
          // A display topology change can invalidate one video frame. The
          // following frame or capture restart owns recovery.
        }
      }
      const rect = this.captureRect();
      gl.uniform1i(this.locations.uDesktop, 0);
      gl.uniform2f(this.locations.uResolution, width, height);
      gl.uniform2f(this.locations.uCaptureOrigin, rect.x, rect.y);
      gl.uniform2f(this.locations.uCaptureSize, rect.width, rect.height);
      gl.uniform1f(this.locations.uTime, (now - this.startedAt) / 1000);
      gl.uniform1f(this.locations.uCaptureReady, captureReady ? 1 : 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      this.frame = requestAnimationFrame(this.render);
    };
  }

  window.CodexBlackHole = Object.freeze({
    create(canvas, codeLayer, options) {
      return new BlackHolePetRenderer(canvas, codeLayer, options);
    }
  });
})();
