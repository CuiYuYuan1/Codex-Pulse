(() => {
  "use strict";

  const TAU = Math.PI * 2;
  const COLORS = Object.freeze({
    outline: "#09102e",
    white: "#fafcfd",
    shade: "#baddeb",
    cyan: "#4fbfea"
  });
  const animeAssetNames = Object.freeze([
    "whole",
    ...Array.from({ length: 8 }, (_, index) => `walk-right-${index}`),
    ...Array.from({ length: 8 }, (_, index) => `walk-left-${index}`),
    ...Array.from({ length: 8 }, (_, index) => `state-thinking-${index}`),
    ...Array.from({ length: 8 }, (_, index) => `state-working-${index}`),
    "state-working", "state-waiting-auth",
    "state-sleeping", "state-stretch", "state-grooming", "state-wave"
  ]);
  const animeAssets = Object.fromEntries(animeAssetNames.map((name) => {
    const image = new Image();
    image.src = `assets/anime-cat/anime-cat-${name}.png`;
    return [name, image];
  }));
  const animePetCharacters = Object.freeze(["dino", "bunny", "ghost", "robot", "fox"]);
  const animePetAssetNames = Object.freeze([
    ...Array.from({ length: 4 }, (_, index) => `state-idle-${index}`),
    ...Array.from({ length: 4 }, (_, index) => `state-thinking-${index}`),
    ...Array.from({ length: 8 }, (_, index) => `state-working-${index}`),
    "state-working", "state-waiting-auth", "state-success", "state-error",
    "state-sleeping", "state-stretch", "state-grooming", "state-curious",
    ...Array.from({ length: 8 }, (_, index) => `walk-right-${index}`),
    ...Array.from({ length: 8 }, (_, index) => `walk-left-${index}`)
  ]);
  const animePetAssets = Object.fromEntries(animePetCharacters.map((character) => [
    character,
    Object.fromEntries([
      ...animePetAssetNames,
      ...(character === "fox"
        ? Array.from({ length: 8 }, (_, index) => `state-idle-loop-${index}`)
        : [])
    ].map((name) => {
      const image = new Image();
      image.src = `assets/anime-pets/anime-${character}-${name}.png`;
      return [name, image];
    }))
  ]));
  const numericKeys = [
    "bodyX", "bodyY", "bodyRotation", "bodyScaleX", "bodyScaleY",
    "headX", "headY", "headRotation", "headScale", "eyeOpen",
    "pupilX", "pupilY", "earLeft", "earRight", "tailSway", "tailLift",
    "frontFarAngle", "frontNearAngle", "hindFarAngle", "hindNearAngle",
    "frontFarLift", "frontNearLift", "hindFarLift", "hindNearLift",
    "pawReach", "mouthOpen", "workSurface", "keyPulse",
    "walkPhase", "walkBlend"
  ];

  const clamp = (value, minimum = 0, maximum = 1) =>
    Math.max(minimum, Math.min(maximum, value));
  const smoothstep = (value) => {
    const x = clamp(value);
    return x * x * (3 - 2 * x);
  };
  const hash = (value) => {
    const x = Math.sin(value * 12.9898 + 78.233) * 43758.5453;
    return x - Math.floor(x);
  };
  const pulse = (phase, center, width) => {
    const distance = Math.abs(phase - center);
    const wrapped = Math.min(distance, 1 - distance);
    return wrapped < width ? .5 + .5 * Math.cos(Math.PI * wrapped / width) : 0;
  };
  const WORKING_FRAME_DURATIONS = Object.freeze([
    .52, .22, .18, .34, .22, .18, .34, .80
  ]);
  const WORKING_CYCLE_DURATION = WORKING_FRAME_DURATIONS
    .reduce((total, duration) => total + duration, 0);
  const FOX_IDLE_FRAME_DURATIONS = Object.freeze([
    .86, .68, .75, 1.05, .64, .82, .71, .96
  ]);
  const FOX_IDLE_CYCLE_DURATION = FOX_IDLE_FRAME_DURATIONS
    .reduce((total, duration) => total + duration, 0);
  const workingSample = (animationTime) => {
    let cursor = ((animationTime % WORKING_CYCLE_DURATION)
      + WORKING_CYCLE_DURATION) % WORKING_CYCLE_DURATION;
    for (let frame = 0; frame < WORKING_FRAME_DURATIONS.length; frame += 1) {
      const duration = WORKING_FRAME_DURATIONS[frame];
      if (cursor < duration) {
        const progress = clamp(cursor / duration);
        const contact = Math.sin(progress * Math.PI);
        const rawBlend = clamp((progress - .52) / .48);
        return {
          frame,
          nextFrame: (frame + 1) % WORKING_FRAME_DURATIONS.length,
          blend: smoothstep(rawBlend),
          left: frame === 2 ? contact : 0,
          right: frame === 5 ? contact : 0
        };
      }
      cursor -= duration;
    }
    return { frame: 7, nextFrame: 0, blend: 0, left: 0, right: 0 };
  };
  const foxIdleSample = (animationTime) => {
    let cursor = ((animationTime % FOX_IDLE_CYCLE_DURATION)
      + FOX_IDLE_CYCLE_DURATION) % FOX_IDLE_CYCLE_DURATION;
    for (let frame = 0; frame < FOX_IDLE_FRAME_DURATIONS.length; frame += 1) {
      const duration = FOX_IDLE_FRAME_DURATIONS[frame];
      if (cursor < duration) {
        return { frame };
      }
      cursor -= duration;
    }
    return { frame: 0 };
  };
  const blink = (time) => {
    const bucket = Math.floor(time / 5);
    const local = time - bucket * 5;
    const start = .45 + hash(bucket) * 3.75;
    const first = Math.max(0, 1 - Math.abs(local - start) / .105);
    const second = hash(bucket + 91) > .78
      ? Math.max(0, 1 - Math.abs(local - start - .24) / .09)
      : 0;
    return 1 - Math.min(1, Math.max(first, second));
  };
  const earFlick = (time) => {
    const bucket = Math.floor(time / 7);
    const local = time - bucket * 7;
    const start = .8 + hash(bucket + 44) * 5.1;
    if (local < start || local > start + .34) return 0;
    return Math.sin(clamp((local - start) / .34) * Math.PI);
  };

  function basePose(time) {
    const breathe = Math.sin(time * TAU / 3.6);
    const ear = earFlick(time);
    return {
      bodyX: 142,
      bodyY: 174 + breathe * 1.25,
      bodyRotation: 0,
      bodyScaleX: 1,
      bodyScaleY: 1 + breathe * .012,
      headX: 181,
      headY: 130 + breathe * .45,
      headRotation: 0,
      headScale: 1,
      eyeOpen: blink(time),
      pupilX: 0,
      pupilY: 0,
      earLeft: -ear * 7,
      earRight: ear * 3,
      tailSway: Math.sin(time * 1.32) * 7 + Math.sin(time * .47) * 3,
      tailLift: 0,
      frontFarAngle: 0,
      frontNearAngle: 0,
      hindFarAngle: 0,
      hindNearAngle: 0,
      frontFarLift: 0,
      frontNearLift: 0,
      hindFarLift: 0,
      hindNearLift: 0,
      pawReach: 0,
      mouthOpen: 0,
      workSurface: 0,
      keyPulse: 0,
      walkPhase: 0,
      walkBlend: 0
    };
  }

  function samplePose(mode, time) {
    const pose = basePose(time);
    const breathe = Math.sin(time * TAU / 3.6);
    switch (mode) {
      case "walk_left":
      case "walk_right": {
        const cycle = time * 1.12;
        pose.walkPhase = cycle % 1;
        pose.walkBlend = 1;
        const stride = Math.sin(cycle * TAU);
        pose.bodyY += Math.abs(stride) * 1.55;
        pose.bodyRotation = stride * .75;
        pose.headY -= Math.abs(stride) * .45;
        pose.headRotation = -pose.bodyRotation * .42;
        pose.tailSway = -Math.sin(cycle * TAU - .65) * 10;
        pose.tailLift = 5;
        break;
      }
      case "thinking":
        pose.headRotation = -8 + Math.sin(time * .8) * 1.5;
        pose.headY += 1;
        pose.pupilX = 2.1;
        pose.pupilY = 1.4;
        pose.earLeft -= 7;
        pose.earRight += 5;
        pose.frontNearAngle = -34;
        pose.frontNearLift = 18;
        pose.pawReach = -2;
        pose.workSurface = .88;
        pose.tailSway = Math.sin(time * 2.8) * 3;
        break;
      case "running": {
        const cycle = time * 3.4;
        const nearTap = Math.max(0, Math.sin(cycle * TAU));
        const farTap = Math.max(0, -Math.sin(cycle * TAU));
        pose.bodyX += 3;
        pose.bodyY += 2;
        pose.bodyRotation = Math.sin(cycle * .62) * 1.1;
        pose.headX += 3;
        pose.headY += 7 + Math.sin(cycle * .5) * 1.3;
        pose.headRotation = 4 + Math.sin(cycle * .42) * 2.2;
        pose.frontNearAngle = -28 + nearTap * 17;
        pose.frontFarAngle = -28 + farTap * 17;
        pose.frontNearLift = 13 - nearTap * 4;
        pose.frontFarLift = 13 - farTap * 4;
        pose.pawReach = 2 + nearTap * 4;
        pose.pupilX = Math.sin(cycle * .7) * 1.8;
        pose.pupilY = 1.3;
        pose.tailSway = Math.sin(cycle * .55) * 6;
        pose.workSurface = 1;
        pose.keyPulse = Math.max(nearTap, farTap);
        break;
      }
      case "waiting":
        pose.bodyX += 3;
        pose.headX += 4;
        pose.headY -= 2;
        pose.headRotation = Math.sin(time * 1.3) * 2;
        pose.earLeft += 4;
        pose.earRight -= 4;
        pose.tailLift = 7;
        pose.tailSway = Math.sin(time * 1.8) * 5;
        break;
      case "waiting_auth": {
        const hesitant = pulse((time / 4.6) % 1, .62, .18);
        pose.bodyY += 2;
        pose.headRotation = 4;
        pose.earLeft -= 7;
        pose.earRight -= 3;
        pose.frontNearAngle = -hesitant * 26;
        pose.frontNearLift = hesitant * 13;
        pose.pawReach = hesitant * 4;
        pose.tailSway = Math.sin(time * 1.2) * 3;
        break;
      }
      case "sniffing": {
        const sniff = Math.sin(time * 5.2);
        pose.bodyX += 5;
        pose.bodyY += 2;
        pose.headX += 12 + sniff * 1.2;
        pose.headY += 18 + Math.abs(sniff) * 2;
        pose.headRotation = 12 + sniff * 2.5;
        pose.pupilX = 2;
        pose.pupilY = 2;
        pose.frontNearAngle = -16;
        pose.frontNearLift = 4;
        pose.tailLift = 8;
        pose.tailSway = Math.sin(time * 2.4) * 4;
        break;
      }
      case "pawing":
      case "dock_play": {
        const cycle = (time / (mode === "pawing" ? 1.25 : 1.9)) % 1;
        const prepare = pulse(cycle, .18, .18);
        const tap = pulse(cycle, mode === "pawing" ? .48 : .36, .22);
        pose.bodyX += 6 + tap * 2;
        pose.bodyY += prepare * 2 - tap;
        pose.bodyRotation = -3 - tap * 2;
        pose.headX += 10 + tap * 3;
        pose.headY += 8;
        pose.headRotation = 8 + tap * 4;
        pose.pupilX = 2.2;
        pose.pupilY = 1;
        pose.frontNearAngle = -44 + tap * 22;
        pose.frontNearLift = 22 - tap * 5;
        pose.pawReach = 6 + tap * 12;
        pose.tailLift = 8;
        break;
      }
      case "pouncing": {
        const cycle = (time / 2.25) % 1;
        const crouch = pulse(cycle, .16, .15);
        const leap = pulse(cycle, .48, .29);
        const land = pulse(cycle, .78, .1);
        pose.bodyX += leap * 14;
        pose.bodyY += crouch * 7 - leap * 17 + land * 4;
        pose.headX += leap * 16;
        pose.headY += crouch * 5 - leap * 18 + land * 2;
        pose.bodyScaleX += crouch * .06 - leap * .025;
        pose.bodyScaleY += -crouch * .08 + leap * .04;
        pose.headRotation = -leap * 4;
        pose.frontFarLift = leap * 12;
        pose.frontNearLift = leap * 15;
        pose.hindFarLift = leap * 8;
        pose.hindNearLift = leap * 8;
        pose.frontNearAngle = -leap * 25;
        pose.frontFarAngle = -leap * 18;
        pose.tailLift = 5 + leap * 10;
        break;
      }
      case "success": {
        const phase = (time / 1.65) % 1;
        const jump = Math.sin(Math.min(1, phase / .72) * Math.PI);
        pose.bodyY -= Math.max(0, jump) * 17;
        pose.headY -= Math.max(0, jump) * 20;
        pose.bodyRotation = Math.sin(phase * TAU) * 3;
        pose.bodyScaleY += (1 - jump) * .035;
        pose.tailLift = 14;
        pose.tailSway = Math.sin(phase * TAU) * 12;
        pose.mouthOpen = 1;
        break;
      }
      case "error":
        pose.bodyY += 6;
        pose.bodyScaleY = .93;
        pose.headY += 7;
        pose.headRotation = 5;
        pose.earLeft -= 16;
        pose.earRight += 16;
        pose.eyeOpen = Math.min(pose.eyeOpen, .72);
        pose.pupilY = 1.8;
        pose.tailLift = -8;
        pose.tailSway = Math.sin(time * .8) * 2;
        break;
      case "sleeping":
        pose.bodyX = 145;
        pose.bodyY = 184 + breathe * 1.6;
        pose.bodyScaleX = 1.1;
        pose.bodyScaleY = .78 + breathe * .016;
        pose.headX = 185;
        pose.headY = 170 + breathe * 1.1;
        pose.headRotation = 7;
        pose.headScale = .9;
        pose.eyeOpen = .03;
        pose.earLeft -= 7;
        pose.earRight += 5;
        pose.tailSway = -28;
        pose.tailLift = -9;
        pose.frontFarLift = 12;
        pose.frontNearLift = 12;
        break;
      case "stretch": {
        const phase = (time / 4.8) % 1;
        const hold = smoothstep(Math.min(1, phase / .25))
          * (1 - smoothstep(Math.max(0, (phase - .78) / .22)));
        pose.bodyX -= hold * 7;
        pose.bodyY -= hold * 9;
        pose.bodyRotation = -hold * 7;
        pose.bodyScaleX += hold * .1;
        pose.headX += hold * 17;
        pose.headY += hold * 28;
        pose.headRotation = hold * 8;
        pose.frontFarAngle = -hold * 31;
        pose.frontNearAngle = -hold * 35;
        pose.pawReach = hold * 15;
        pose.tailLift = hold * 16;
        pose.eyeOpen = Math.min(pose.eyeOpen, 1 - hold * .5);
        break;
      }
      case "grooming": {
        const cycle = time * 1.2;
        const lift = .5 + .5 * Math.sin(cycle);
        pose.frontNearAngle = -34 - lift * 18;
        pose.frontNearLift = 18 + lift * 8;
        pose.pawReach = -4;
        pose.headX -= lift * 10;
        pose.headY += lift * 11;
        pose.headRotation = -10 - lift * 10;
        pose.eyeOpen = Math.min(pose.eyeOpen, .62);
        pose.mouthOpen = pulse((cycle / TAU) % 1, .56, .18);
        break;
      }
      case "hop": {
        const phase = (time / 2.3) % 1;
        const crouch = pulse(phase, .14, .14);
        const air = pulse(phase, .48, .3);
        const land = pulse(phase, .79, .1);
        pose.bodyY += crouch * 7 - air * 24 + land * 5;
        pose.headY += crouch * 5 - air * 27 + land * 3;
        pose.bodyScaleY += crouch * -.08 + air * .05 + land * -.07;
        pose.bodyScaleX += crouch * .05 + air * -.03 + land * .05;
        pose.frontFarLift = pose.frontNearLift = air * 13;
        pose.hindFarLift = pose.hindNearLift = air * 9;
        pose.tailLift = air * 12;
        break;
      }
      case "wave": {
        const cycle = time * 2.1;
        const wave = .5 + .5 * Math.sin(cycle * TAU);
        pose.bodyRotation = -3;
        pose.headRotation = 3;
        pose.frontNearAngle = -47 + wave * 19;
        pose.frontNearLift = 25;
        pose.pawReach = -5;
        pose.tailSway = Math.sin(cycle * 1.1) * 8;
        break;
      }
      case "curious": {
        const cycle = time * .72;
        pose.headRotation = Math.sin(cycle) * 7;
        pose.headX += Math.sin(cycle * .55) * 3;
        pose.headY -= Math.abs(Math.sin(cycle)) * 2;
        pose.pupilX = Math.sin(cycle * 1.4) * 2;
        pose.pupilY = Math.cos(cycle * .8) * 1.2;
        pose.earLeft += Math.sin(cycle * 1.15) * 4;
        pose.earRight -= Math.sin(cycle * .92) * 4;
        pose.tailSway = Math.sin(cycle * 1.6 - .7) * 9;
        break;
      }
      case "idle":
      default: {
        const beat = pulse((time / 9.5) % 1, .72, .11);
        pose.headRotation += beat * 4;
        pose.pupilX += beat * 1.2;
        break;
      }
    }
    return pose;
  }

  function mixPose(from, to, amount) {
    const result = {};
    for (const key of numericKeys) result[key] = from[key] + (to[key] - from[key]) * amount;
    return result;
  }

  const isLocomotionState = (state) =>
    state === "walk_left" || state === "walk_right";
  const isRestingState = (state) =>
    state === "sleeping" || state === "stretch" || state === "grooming";
  const isFocusedState = (state) =>
    state === "thinking"
      || state === "running"
      || state === "waiting"
      || state === "waiting_auth";

  function transitionBridgeState(from, to) {
    if (isLocomotionState(to)) return to;
    if (isLocomotionState(from)) return from;
    if (to === "sleeping" || from === "sleeping") return "stretch";
    if (isFocusedState(to) || isFocusedState(from)) return "curious";
    if (to === "pawing" || to === "dock_play" || to === "pouncing") {
      return "sniffing";
    }
    if (isRestingState(to) || isRestingState(from)) return "stretch";
    return "curious";
  }

  function transitionVisualState(from, to, progress) {
    if (from === to) return to;
    if (progress < .30) return from;
    if (progress < .68) return transitionBridgeState(from, to);
    return to;
  }

  function catTransitionBridgePose(from, to) {
    if (to === "sleeping" || from === "sleeping" || isRestingState(to)) {
      return samplePose("stretch", 1.2);
    }

    const pose = samplePose("idle", 0);
    if (isLocomotionState(to)) {
      pose.bodyX -= 3.2;
      pose.bodyY += 1.8;
      pose.bodyRotation = -1.8;
      pose.headX += 2.4;
      pose.frontNearAngle = -13;
      pose.frontNearLift = 5.5;
      pose.hindFarAngle = 4;
      pose.tailLift = 7;
      pose.tailSway = 8;
      return pose;
    }
    if (isLocomotionState(from)) {
      pose.bodyX += 1.4;
      pose.bodyY += 1.2;
      pose.frontNearAngle = -4;
      pose.frontFarAngle = 3;
      pose.tailLift = 4;
      pose.tailSway = -5;
      return pose;
    }
    if (isFocusedState(to)) {
      pose.bodyX += 2.2;
      pose.bodyY += 1.4;
      pose.headX += 4.8;
      pose.headY += 3.8;
      pose.headRotation = -4.5;
      pose.earLeft -= 5;
      pose.earRight += 3;
      pose.frontNearAngle = -20;
      pose.frontNearLift = 8;
      pose.tailSway = 3;
      pose.workSurface = to === "running" ? .28 : 0;
      return pose;
    }
    if (isFocusedState(from)) {
      pose.headRotation = 3;
      pose.headX += 2;
      pose.frontNearAngle = -8;
      pose.frontNearLift = 3;
      pose.tailSway = 5;
      return pose;
    }
    pose.headRotation = 4;
    pose.headX += 2.5;
    pose.pupilX = 1.4;
    pose.earLeft -= 3;
    pose.tailSway = 6;
    return pose;
  }

  function sampleTransitionPose(from, to, fromPose, elapsed, progress) {
    if (from === to) return samplePose(to, elapsed);
    const bridge = catTransitionBridgePose(from, to);
    if (progress < .38) {
      return mixPose(fromPose, bridge, smoothstep(progress / .38));
    }
    const target = samplePose(to, Math.max(0, elapsed - .236));
    return mixPose(
      bridge,
      target,
      smoothstep((progress - .38) / .62)
    );
  }

  function animeTransitionMotion(character, from, to, progress) {
    const p = clamp(progress);
    const weightShift = Math.sin(Math.PI * p);
    const enteringLocomotion = isLocomotionState(to) && !isLocomotionState(from);
    const leavingLocomotion = isLocomotionState(from) && !isLocomotionState(to);
    const locomotionChange = enteringLocomotion || leavingLocomotion;
    if (character === "fox") {
      return {
        x: weightShift * (enteringLocomotion ? 4.2 : 2.8),
        y: weightShift * 2.1,
        rotation: weightShift * (enteringLocomotion ? -1.5 : -.8)
      };
    }
    if (character === "bunny") {
      const compression = Math.sin(Math.PI * Math.min(1, p * 1.35));
      const landing = leavingLocomotion
        ? Math.sin(Math.PI * Math.max(0, (p - .45) / .55))
        : 0;
      return {
        x: locomotionChange ? weightShift * 1.8 : 0,
        y: compression * 3.4 + landing * 1.4,
        rotation: weightShift * (enteringLocomotion ? -.8 : .55)
      };
    }
    if (character === "dino") {
      return {
        x: weightShift * (locomotionChange ? 3.2 : 1.7),
        y: weightShift * .8,
        rotation: weightShift * (enteringLocomotion ? -1.25 : .55)
      };
    }
    if (character === "ghost") {
      return {
        x: Math.sin(Math.PI * p) * 2.2,
        y: -Math.sin(Math.PI * p) * 2.8,
        rotation: Math.sin(Math.PI * 2 * p) * .9
      };
    }
    if (character === "robot") {
      const servo = Math.sin(Math.PI * Math.min(1, p * 2))
        - Math.sin(Math.PI * Math.max(0, (p - .5) * 2)) * .45;
      return {
        x: servo * 1.7,
        y: Math.abs(servo) * .65,
        rotation: servo * .38
      };
    }
    return { x: 0, y: 0, rotation: 0 };
  }

  function transitionDurationMs(character, from, to) {
    const base = {
      cat: 620,
      dino: 580,
      bunny: 660,
      ghost: 520,
      robot: 460,
      fox: 640
    }[character] || 600;
    return isRestingState(from) || isRestingState(to) ? base + 140 : base;
  }

  function roundedRect(ctx, x, y, width, height, radius) {
    const r = Math.min(radius, width / 2, height / 2);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + width, y, x + width, y + height, r);
    ctx.arcTo(x + width, y + height, x, y + height, r);
    ctx.arcTo(x, y + height, x, y, r);
    ctx.arcTo(x, y, x + width, y, r);
    ctx.closePath();
  }

  function fillStroke(ctx, fill, width = 5) {
    ctx.fillStyle = fill;
    ctx.fill();
    ctx.strokeStyle = COLORS.outline;
    ctx.lineWidth = width;
    ctx.lineJoin = "round";
    ctx.stroke();
  }

  function drawTail(ctx, pose) {
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(pose.bodyX - 45, pose.bodyY - 2);
    ctx.bezierCurveTo(
      pose.bodyX - 69, pose.bodyY + 4,
      pose.bodyX - 94 + pose.tailSway, pose.bodyY - 2 - pose.tailLift * .7,
      pose.bodyX - 88 + pose.tailSway * .45, pose.bodyY - 28 - pose.tailLift
    );
    ctx.strokeStyle = COLORS.outline;
    ctx.lineWidth = 19;
    ctx.lineCap = "round";
    ctx.stroke();
    ctx.strokeStyle = COLORS.white;
    ctx.lineWidth = 12;
    ctx.stroke();
    ctx.restore();
  }

  function drawLeg(ctx, x, angle, lift, far, pose) {
    ctx.save();
    ctx.translate(x, pose.bodyY + 18 - lift);
    ctx.rotate(angle * Math.PI / 180);
    roundedRect(ctx, -10, -5, 20, 43, 10);
    fillStroke(ctx, far ? COLORS.shade : COLORS.white, far ? 4 : 5);
    ctx.beginPath();
    ctx.ellipse(0, 35.5, 14, 7.5, 0, 0, TAU);
    fillStroke(ctx, far ? COLORS.shade : COLORS.white, far ? 4 : 5);
    ctx.restore();
  }

  function drawBody(ctx, pose) {
    ctx.save();
    ctx.translate(pose.bodyX, pose.bodyY);
    ctx.rotate(pose.bodyRotation * Math.PI / 180);
    ctx.scale(pose.bodyScaleX, pose.bodyScaleY);
    ctx.beginPath();
    ctx.ellipse(0, 0, 53, 36, 0, 0, TAU);
    fillStroke(ctx, COLORS.white);
    ctx.globalAlpha = .58;
    ctx.fillStyle = COLORS.shade;
    ctx.beginPath();
    ctx.ellipse(29.5, -1.5, 11.5, 21.5, 0, 0, TAU);
    ctx.fill();
    ctx.restore();
  }

  function drawEar(ctx, x, rotation, mirror) {
    ctx.save();
    ctx.translate(x, -28);
    ctx.rotate(rotation * Math.PI / 180);
    if (mirror) ctx.scale(-1, 1);
    ctx.beginPath();
    ctx.moveTo(-16, 6);
    ctx.lineTo(-7, -31);
    ctx.lineTo(17, 3);
    ctx.closePath();
    fillStroke(ctx, COLORS.white);
    ctx.beginPath();
    ctx.moveTo(-8, 0);
    ctx.lineTo(-5, -19);
    ctx.lineTo(8, 0);
    ctx.closePath();
    ctx.fillStyle = COLORS.cyan;
    ctx.fill();
    ctx.restore();
  }

  function drawEye(ctx, x, pose) {
    ctx.save();
    ctx.translate(x + pose.pupilX, -1 + pose.pupilY);
    ctx.scale(1, Math.max(.045, pose.eyeOpen));
    ctx.fillStyle = COLORS.outline;
    ctx.beginPath();
    ctx.ellipse(0, .5, 8, 10.5, 0, 0, TAU);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.ellipse(-1.4, -4.4, 2.1, 2.1, 0, 0, TAU);
    ctx.fill();
    ctx.restore();
  }

  function drawHead(ctx, pose) {
    ctx.save();
    ctx.translate(pose.headX, pose.headY);
    ctx.rotate(pose.headRotation * Math.PI / 180);
    ctx.scale(pose.headScale, pose.headScale);
    drawEar(ctx, -26, -7 + pose.earLeft, false);
    drawEar(ctx, 27, 7 + pose.earRight, true);
    roundedRect(ctx, -46, -36, 92, 77, 31);
    fillStroke(ctx, COLORS.white);
    drawEye(ctx, -20, pose);
    drawEye(ctx, 20, pose);
    roundedRect(ctx, -5, 11, 10, 7, 3);
    ctx.fillStyle = COLORS.outline;
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(0, 18);
    ctx.bezierCurveTo(4, 23 + pose.mouthOpen * 3, 9, 23 + pose.mouthOpen * 3, 12, 18 + pose.mouthOpen * 3);
    ctx.strokeStyle = COLORS.outline;
    ctx.lineWidth = 3;
    ctx.lineCap = "round";
    ctx.stroke();
    for (const side of [-1, 1]) {
      for (const offset of [-5, 2, 9]) {
        ctx.beginPath();
        ctx.moveTo(side * 31, 16 + offset * .35);
        ctx.lineTo(side * 53, 14 + offset);
        ctx.strokeStyle = COLORS.outline;
        ctx.lineWidth = 2.4;
        ctx.stroke();
      }
    }
    ctx.restore();
  }

  function drawKeyboard(ctx, pose, facesLeft) {
    if (pose.workSurface <= .01) return;
    ctx.save();
    if (!facesLeft) {
      ctx.translate(285, 0);
      ctx.scale(-1, 1);
    }
    ctx.globalAlpha = pose.workSurface;
    roundedRect(ctx, 42, 220, 104, 27, 8);
    ctx.fillStyle = COLORS.outline;
    ctx.fill();
    ctx.strokeStyle = COLORS.cyan;
    ctx.globalAlpha = pose.workSurface * .84;
    ctx.lineWidth = 2.4;
    ctx.stroke();
    ctx.globalAlpha = pose.workSurface;
    for (let row = 0; row < 2; row += 1) {
      for (let column = 0; column < 7; column += 1) {
        const active = (column + row * 2) % 4 === Math.floor(pose.keyPulse * 3.9);
        roundedRect(ctx, 50 + column * 12.5, 225 + row * 8.2, 8.5, 5.2, 1.8);
        ctx.fillStyle = active ? COLORS.cyan : COLORS.shade;
        ctx.globalAlpha = pose.workSurface * (active ? 1 : .62);
        ctx.fill();
      }
    }
    ctx.restore();
  }

  function drawAnimePart(ctx, image, x, y, width, height, rotation = 0, opacity = 1) {
    if (!image.complete || !image.naturalWidth) return false;
    ctx.save();
    ctx.globalAlpha *= opacity;
    ctx.translate(x, y);
    ctx.rotate(rotation * Math.PI / 180);
    ctx.drawImage(image, -width / 2, -height / 2, width, height);
    ctx.restore();
    return true;
  }

  function drawAnimeLeg(ctx, image, x, y, width, height, angle, lift, opacity) {
    if (!image.complete || !image.naturalWidth) return false;
    ctx.save();
    ctx.globalAlpha *= opacity;
    ctx.translate(x, y - lift);
    ctx.rotate(angle * Math.PI / 180);
    ctx.drawImage(image, -width / 2, -7, width, height);
    ctx.restore();
    return true;
  }

  function drawAnimeHead(ctx, pose) {
    const image = animeAssets.head;
    if (!image.complete || !image.naturalWidth) return false;
    ctx.save();
    ctx.translate(128 + pose.headX - 181, 117 + pose.headY - 130);
    ctx.rotate(pose.headRotation * Math.PI / 180);
    ctx.scale(pose.headScale, pose.headScale);
    ctx.drawImage(image, -61, -54, 122, 112);
    const blinkAmount = clamp(1 - pose.eyeOpen);
    if (blinkAmount > .04) {
      ctx.globalAlpha *= blinkAmount;
      for (const eyeX of [-23, 23]) {
        ctx.fillStyle = "#f4f9ff";
        ctx.beginPath();
        ctx.ellipse(eyeX, 5, 12, 10, 0, 0, TAU);
        ctx.fill();
        ctx.beginPath();
        ctx.moveTo(eyeX - 10, 4);
        ctx.quadraticCurveTo(eyeX, 10, eyeX + 10, 4);
        ctx.strokeStyle = COLORS.outline;
        ctx.lineWidth = 2.4;
        ctx.lineCap = "round";
        ctx.stroke();
      }
    }
    ctx.restore();
    return true;
  }

  function stateAssetName(state) {
    switch (state) {
      case "waiting":
      case "waiting_auth": return "state-waiting-auth";
      case "sleeping": return "state-sleeping";
      case "stretch": return "state-stretch";
      case "grooming": return "state-grooming";
      case "wave":
      case "success": return "state-wave";
      default: return null;
    }
  }

  function drawAnimeCat(ctx, pose, facesLeft, state, animationTime, opacity = 1) {
    const wholeImage = animeAssets.whole;
    if (!wholeImage.complete || !wholeImage.naturalWidth) return false;

    if (opacity <= .01) return true;
    const isWalking = state === "walk_left" || state === "walk_right";
    if (isWalking) {
      const phase = ((animationTime * 1.12 % 1) + 1) % 1;
      const frameIndex = Math.min(7, Math.max(0, Math.floor(phase * 8)));
      const direction = state === "walk_left" ? "left" : "right";
      const walkImage = animeAssets[`walk-${direction}-${frameIndex}`];
      if (walkImage?.complete && walkImage.naturalWidth) {
        ctx.save();
        ctx.globalAlpha *= opacity;
        ctx.drawImage(walkImage, 40, 54, 184, 199);
        ctx.restore();
      }
      return true;
    }

    const stateName = state === "thinking"
      ? `state-thinking-${Math.min(7, Math.max(0, Math.floor(animationTime / 1.18) % 8))}`
      : state === "running"
      ? `state-working-${workingSample(animationTime).frame}`
      : stateAssetName(state);
    const stateImage = stateName ? animeAssets[stateName] : null;
    if (stateImage?.complete && stateImage.naturalWidth) {
      const motionX = state === "running" ? 0 : clamp(
        (pose.bodyX - 142) * .28 + (pose.headX - 181) * .06,
        -5,
        6
      );
      const motionY = state === "running" ? 0 : clamp(
        (pose.bodyY - 174) * .48 + (pose.headY - 130) * .08,
        -15,
        14
      );
      const rotation = state === "running" ? 0 : clamp(
        pose.bodyRotation * .26 + pose.headRotation * .035,
        -1.8,
        1.8
      );
      ctx.save();
      ctx.globalAlpha *= opacity;
      ctx.translate(132 + motionX, 154 + motionY);
      ctx.rotate(rotation * Math.PI / 180);
      ctx.drawImage(stateImage, -92, -99.5, 184, 199);
      if (state === "running") {
        drawWorkingKeyPulse(ctx, "cat", workingSample(animationTime));
      }
      ctx.restore();
      return true;
    }

    const motionX = clamp(
      (pose.bodyX - 142) * .34 + (pose.headX - 181) * .10,
      -6,
      8
    );
    const motionY = clamp(
      (pose.bodyY - 174) * .52 + (pose.headY - 130) * .12,
      -15,
      14
    );
    const rotation = clamp(
      pose.bodyRotation * .38 + pose.headRotation * .06,
      -2.4,
      2.4
    );
    const uniformScale = clamp(
      1 + (pose.bodyScaleX + pose.bodyScaleY - 2) * .10,
      .975,
      1.035
    );
    ctx.save();
    ctx.globalAlpha *= opacity;
    if (!facesLeft) {
      ctx.translate(285, 0);
      ctx.scale(-1, 1);
    }
    ctx.translate(132 + motionX, 156 + motionY);
    ctx.rotate(rotation * Math.PI / 180);
    ctx.scale(uniformScale, uniformScale);
    ctx.drawImage(wholeImage, -93, -96, 186, 192);
    ctx.restore();
    return true;
  }

  function animePetStateAsset(character, state, animationTime) {
    if (state === "thinking") {
      const holds = { dino: 1.75, bunny: 1.55, ghost: 1.85, robot: 1.35, fox: 1.45 };
      const frame = Math.floor(animationTime / (holds[character] || 1.6)) % 4;
      return `state-thinking-${frame}`;
    }
    switch (state) {
      case "waiting":
      case "waiting_auth": return "state-waiting-auth";
      case "success":
      case "wave":
      case "hop": return "state-success";
      case "error": return "state-error";
      case "sleeping": return "state-sleeping";
      case "stretch": return "state-stretch";
      case "grooming":
        return character === "fox" ? "state-idle-loop-5" : "state-grooming";
      case "curious":
        return character === "fox" ? "state-idle-loop-3" : "state-curious";
      case "sniffing":
      case "pawing":
      case "dock_play":
        return character === "fox" ? "walk-left-0" : "state-curious";
      case "pouncing": return "state-success";
      default:
        return "state-idle-0";
    }
  }

  function animePetLocomotionDuration(character) {
    return ({ dino: 1.06, bunny: 1.38, ghost: 1.24, robot: .94, fox: 1.12 })[character] || 1;
  }

  function drawWorkingKeyPulse(ctx, character, sample) {
    const positions = {
      dino: [-10, 35],
      bunny: [-22, 26],
      ghost: [-33, 30],
      robot: [-33, 34],
      cat: [-25, 16],
      fox: [-39, 12]
    }[character] || [-20, 18];
    const keyY = {
      cat: 66,
      dino: 68,
      bunny: 65,
      ghost: 68,
      robot: 70,
      fox: 74
    }[character] || 68;
    for (const [x, strength] of [[positions[0], sample.left], [positions[1], sample.right]]) {
      if (strength <= .015) continue;
      ctx.save();
      ctx.fillStyle = `rgba(41, 210, 255, ${.10 + strength * .22})`;
      ctx.beginPath();
      ctx.roundRect(x - 4.2, keyY - 2.2, 8.4, 4.4, 1.6);
      ctx.fill();
      ctx.fillStyle = `rgba(41, 210, 255, ${.40 + strength * .60})`;
      ctx.beginPath();
      ctx.roundRect(x - 3, keyY - 1.35, 6, 2.7, 1.1);
      ctx.fill();
      ctx.restore();
    }
  }

  function drawAnimePet(
    ctx,
    character,
    state,
    animationTime,
    opacity = 1,
    facesLeft = false
  ) {
    const assets = animePetAssets[character];
    if (!assets || opacity <= .01) return false;
    let image;
    const walking = state === "walk_left" || state === "walk_right";
    if (walking) {
      const duration = animePetLocomotionDuration(character);
      const phase = ((animationTime / duration % 1) + 1) % 1;
      const framePosition = phase * 8;
      const frame = Math.min(7, Math.max(0, Math.floor(framePosition)));
      const direction = state === "walk_left" ? "left" : "right";
      image = assets[`walk-${direction}-${frame}`];
    } else if (state === "thinking") {
      const holds = { dino: 1.75, bunny: 1.55, ghost: 1.85, robot: 1.35, fox: 1.45 };
      const framePosition = animationTime / (holds[character] || 1.6);
      const frame = Math.floor(framePosition) % 4;
      image = assets[`state-thinking-${frame}`];
    } else if (state === "running") {
      const sample = workingSample(animationTime);
      image = assets[`state-working-${sample.frame}`];
    } else if (character === "fox" && state === "idle") {
      const sample = foxIdleSample(animationTime);
      image = assets[`state-idle-loop-${sample.frame}`];
    } else {
      image = assets[animePetStateAsset(character, state, animationTime)];
    }
    if (!image?.complete || !image.naturalWidth) return false;

    const breathDuration = ({ dino: 3.8, bunny: 3.2, ghost: 4.6, robot: 2.8, fox: 3.6 })[character];
    const breathe = Math.sin(animationTime * TAU / breathDuration);
    let x = 0;
    let y = breathe * .75;
    let rotation = 0;
    const baseScale = character === "fox" ? 1.14 : 1;
    let scaleX = baseScale;
    let scaleY = baseScale + breathe * .006;
    if (walking) {
      const phase = animationTime / animePetLocomotionDuration(character) * TAU;
      if (character === "dino") {
        y = Math.abs(Math.sin(phase)) * .9;
        rotation = Math.sin(phase) * .35;
      } else if (character === "bunny") {
        y = -Math.max(0, Math.sin(phase)) * 3.4 + Math.max(0, -Math.sin(phase)) * .8;
        rotation = Math.sin(phase - .35) * .55;
      } else if (character === "ghost") {
        y = Math.sin(phase) * 2.4;
        rotation = Math.sin(phase - .55) * 1.1;
        scaleX = 1 + Math.cos(phase) * .012;
        scaleY = 1 - Math.cos(phase) * .016;
      } else if (character === "robot") {
        y = Math.abs(Math.sin(phase)) * .65;
        rotation = Math.sin(phase) * .24;
      } else if (character === "fox") {
        y = Math.abs(Math.sin(phase)) * .8;
        rotation = Math.sin(phase - .2) * .32;
      }
    } else if (state === "thinking") {
      const amount = ({ dino: .7, bunny: .9, ghost: 1.3, robot: .35, fox: .8 })[character];
      rotation = Math.sin(animationTime * .72) * amount;
      y += Math.sin(animationTime * 1.15) * .5;
    } else if (state === "running") {
      y = breathe * .35;
      rotation = 0;
    } else if (state === "waiting" || state === "waiting_auth") {
      y += Math.sin(animationTime * 1.35) * .65;
    } else if (state === "success") {
      y -= Math.max(0, Math.sin(animationTime * 2.4)) * (character === "ghost" ? 3.2 : 1.8);
    } else if (state === "sniffing") {
      const sniff = Math.sin(animationTime * 5.2);
      x = 4.5 + sniff * 1.2;
      y += 3.2 + Math.abs(sniff) * 1.3;
      rotation = 1.8 + sniff * .7;
      scaleX *= 1.015;
      scaleY *= .985;
    } else if (state === "pawing") {
      const phase = (animationTime / 1.25) % 1;
      const prepare = pulse(phase, .18, .18);
      const tap = pulse(phase, .48, .22);
      x = 3.5 + tap * 7.5;
      y += prepare * 1.8 - tap * 1.2;
      rotation = -1.5 - tap * 2.2;
      scaleX *= 1 + tap * .018;
      scaleY *= 1 - tap * .014;
    } else if (state === "pouncing") {
      const phase = (animationTime / 2.25) % 1;
      const crouch = pulse(phase, .16, .15);
      const leap = pulse(phase, .48, .29);
      const land = pulse(phase, .78, .1);
      x = leap * 10;
      y += crouch * 4.5 - leap * 11 + land * 3;
      rotation = -leap * 2.5;
      scaleX *= 1 + crouch * .045 - leap * .018;
      scaleY *= 1 - crouch * .055 + leap * .026;
    } else if (state === "dock_play") {
      const phase = (animationTime / 1.9) % 1;
      const reach = pulse(phase, .28, .22);
      const recoil = pulse(phase, .66, .20);
      x = reach * 6 - recoil * 2;
      y += -reach * 3 + recoil * 1.5;
      rotation = reach * 2.2 - recoil * 1.2;
    }

    ctx.save();
    ctx.globalAlpha *= opacity;
    ctx.translate(132 + x, 154 + y);
    ctx.rotate(rotation * Math.PI / 180);
    const directionalInteraction = state === "sniffing"
      || state === "pawing"
      || state === "pouncing"
      || state === "dock_play";
    ctx.scale(directionalInteraction && !facesLeft ? -scaleX : scaleX, scaleY);
    ctx.drawImage(image, -92, -99.5, 184, 199);
    if (state === "running") {
      drawWorkingKeyPulse(ctx, character, workingSample(animationTime));
    }
    ctx.restore();
    return true;
  }

  const FOOTSTEP_LIFETIME = 1.22;
  const FOOTSTEP_TRAIL_SPEED = 185;

  function footstepGroundY(character) {
    return character === "ghost" ? 244 : character === "cat" ? 249 : 251;
  }

  function strokeFootstepPath(ctx, darkWidth = 2.15, lightWidth = .62) {
    ctx.strokeStyle = "rgba(2, 4, 12, .94)";
    ctx.lineWidth = darkWidth;
    ctx.stroke();
    ctx.strokeStyle = "rgba(158, 230, 255, .82)";
    ctx.lineWidth = lightWidth;
    ctx.stroke();
  }

  function drawFootstepDent(ctx, character, x, y, expansion, impact) {
    const width = (character === "robot" ? 52 : character === "dino" ? 58 : 47) * expansion;
    const height = (character === "ghost" ? 7 : 11) * expansion;
    ctx.beginPath();
    ctx.ellipse(x, y, width / 2, height / 2, 0, 0, TAU);
    ctx.fillStyle = `rgba(4, 7, 17, ${.36 + impact * .18})`;
    ctx.fill();
    ctx.strokeStyle = "rgba(255, 255, 255, .62)";
    ctx.lineWidth = 1.15;
    ctx.stroke();
  }

  function drawFootstepCracks(ctx, x, y, seed, expansion) {
    ctx.beginPath();
    for (let index = 0; index < 6; index += 1) {
      const angle = index * Math.PI / 3 + (((seed + index * 7) % 5) - 2) * .055;
      const length = (13 + ((seed * 5 + index * 7) % 14)) * expansion;
      const kink = length * .56;
      const midX = x + Math.cos(angle) * kink;
      const midY = y + Math.sin(angle) * kink * .42;
      const endAngle = angle + (index % 2 === 0 ? .10 : -.08);
      ctx.moveTo(x, y);
      ctx.lineTo(midX, midY);
      ctx.lineTo(
        x + Math.cos(endAngle) * length,
        y + Math.sin(angle) * length * .46
      );
    }
    strokeFootstepPath(ctx, 3.4, 1.15);
  }

  function drawFootprint(ctx, character, x, y, expansion) {
    expansion *= 1.22;
    const fill = "rgba(4, 7, 18, .42)";
    const rim = "rgba(148, 214, 255, .48)";
    ctx.fillStyle = fill;
    ctx.strokeStyle = rim;
    ctx.lineWidth = .7;
    if (character === "robot") {
      ctx.beginPath();
      ctx.rect(x - 14 * expansion, y - 5 * expansion, 28 * expansion, 9 * expansion);
      ctx.fill();
      ctx.stroke();
    } else if (character === "bunny") {
      for (const offset of [-6, 6]) {
        ctx.beginPath();
        ctx.ellipse(
          x + offset,
          y - expansion,
          4 * expansion,
          7 * expansion,
          0,
          0,
          TAU
        );
        ctx.fill();
        ctx.stroke();
      }
    } else if (character === "dino") {
      ctx.beginPath();
      for (const offset of [-9, 0, 9]) {
        ctx.moveTo(x + offset, y + 2);
        ctx.lineTo(x + offset - 3 * expansion, y - 7 * expansion);
        ctx.lineTo(x + offset + 3 * expansion, y - 7 * expansion);
        ctx.closePath();
      }
      ctx.fill();
      ctx.stroke();
    } else if (character === "ghost") {
      ctx.beginPath();
      ctx.ellipse(x, y, 18 * expansion, 3 * expansion, 0, 0, TAU);
      ctx.lineWidth = 1.15;
      ctx.stroke();
    } else {
      ctx.beginPath();
      ctx.ellipse(x, y, 7 * expansion, 4.5 * expansion, 0, 0, TAU);
      ctx.fill();
      for (const offset of [-6, 0, 6]) {
        ctx.beginPath();
        ctx.ellipse(
          x + offset,
          y - 5.7 * expansion,
          2.2 * expansion,
          2.3 * expansion,
          0,
          0,
          TAU
        );
        ctx.fill();
      }
    }
  }

  function drawPressureArcs(ctx, x, y, expansion) {
    for (const width of [48, 66]) {
      ctx.beginPath();
      ctx.ellipse(x, y, width * expansion / 2, 4 * expansion, 0, 0, TAU);
      ctx.strokeStyle = `rgba(255, 255, 255, ${width < 40 ? .26 : .16})`;
      ctx.lineWidth = .65;
      ctx.stroke();
    }
  }

  function drawFootstepTrail(ctx, character, state, elapsedSeconds) {
    if (state !== "walk_left" && state !== "walk_right") return;
    const movesLeft = state === "walk_left";
    const cycleDuration = character === "cat"
      ? 1 / 1.12
      : animePetLocomotionDuration(character);
    const contactInterval = cycleDuration / 2;
    const newestStep = Math.floor(elapsedSeconds / contactInterval);
    for (let offset = -1; offset < 2; offset += 1) {
      const step = newestStep - offset;
      if (step < 0) continue;
      const age = elapsedSeconds - step * contactInterval;
      if (age < 0 || age > FOOTSTEP_LIFETIME) continue;
      const sideX = step % 2 === 0 ? 111 : 153;
      const mirroredX = movesLeft ? 264 - sideX : sideX;
      const x = mirroredX + age * FOOTSTEP_TRAIL_SPEED * (movesLeft ? 1 : -1);
      const y = footstepGroundY(character);
      const life = Math.max(0, 1 - age / FOOTSTEP_LIFETIME);
      const impact = age < 0 ? 0 : Math.max(0, Math.min(1, 1 - age / .14));
      const expansion = .72 + Math.min(1, age / .20) * .28;
      ctx.save();
      // A linear tail stays readable between alternating paw contacts. The
      // old squared fade vanished against white applications.
      ctx.globalAlpha *= age < 0 ? 1 : Math.max(.18, life);
      const style = ((step % 3) + 3) % 3;
      if (style === 0) {
        drawFootstepDent(ctx, character, x, y, expansion, impact);
        drawFootstepCracks(ctx, x, y - 1, step, expansion);
      } else if (style === 1) {
        drawFootstepDent(ctx, character, x, y, expansion * .94, impact);
        drawFootstepCracks(ctx, x, y - 1, step + 17, expansion * 1.08);
      } else {
        drawFootstepDent(ctx, character, x, y, expansion * .88, impact);
        drawFootprint(ctx, character, x, y, expansion);
        drawFootstepCracks(ctx, x, y - 1, step + 31, expansion * .74);
        drawPressureArcs(ctx, x, y, expansion);
      }
      ctx.restore();
    }
  }

  function drawCat(
    ctx,
    pose,
    state,
    previousState,
    transition,
    elapsedSeconds,
    previousElapsedSeconds,
    character,
    facesLeft
  ) {
    ctx.clearRect(0, 0, 480, 288);
    ctx.save();
    const stateChanged = state !== previousState;
    const visualState = stateChanged
      ? transitionVisualState(previousState, state, transition)
      : state;
    const visualTime = visualState === state
      ? elapsedSeconds
      : previousElapsedSeconds + elapsedSeconds;
    drawFootstepTrail(ctx, character, visualState, visualTime);
    if (character === "cat") {
      drawAnimeCat(
        ctx,
        pose,
        visualState === "walk_left"
          ? true
          : visualState === "walk_right"
          ? false
          : facesLeft,
        visualState,
        visualTime,
        1
      );
    } else {
      const motion = stateChanged
        ? animeTransitionMotion(character, previousState, state, transition)
        : { x: 0, y: 0, rotation: 0 };
      ctx.translate(132 + motion.x, 154 + motion.y);
      ctx.rotate(motion.rotation * Math.PI / 180);
      ctx.translate(-132, -154);
      drawAnimePet(ctx, character, visualState, visualTime, 1, facesLeft);
    }
    ctx.restore();
  }

  function create(canvas, { reduceMotion = false } = {}) {
    const context = canvas.getContext("2d", { alpha: true, desynchronized: true });
    let visible = false;
    let character = "cat";
    let facesLeft = false;
    let targetState = "idle";
    let previousState = "idle";
    let fromPose = samplePose("idle", 0);
    let transitionStartedAt = performance.now();
    let previousStateElapsedAtTransition = 0;
    let frame;

    const sampleCurrent = (nowMs) => {
      const elapsed = Math.max(0, (nowMs - transitionStartedAt) / 1000);
      const amount = reduceMotion
        ? 1
        : smoothstep(
          (nowMs - transitionStartedAt)
            / transitionDurationMs(character, previousState, targetState)
        );
      return sampleTransitionPose(
        previousState,
        targetState,
        fromPose,
        reduceMotion ? 0 : elapsed,
        amount
      );
    };
    const transitionAmount = (nowMs) =>
      reduceMotion
        ? 1
        : smoothstep(
          (nowMs - transitionStartedAt)
            / transitionDurationMs(character, previousState, targetState)
        );

    const tick = (nowMs) => {
      frame = null;
      if (!visible) return;
      drawCat(
        context,
        sampleCurrent(nowMs),
        targetState,
        previousState,
        transitionAmount(nowMs),
        Math.max(0, (nowMs - transitionStartedAt) / 1000),
        previousStateElapsedAtTransition,
        character,
        facesLeft
      );
      if (!reduceMotion) frame = requestAnimationFrame(tick);
    };

    const requestDraw = () => {
      if (frame || !visible) return;
      frame = requestAnimationFrame(tick);
    };
    for (const image of [
      ...Object.values(animeAssets),
      ...Object.values(animePetAssets).flatMap((assets) => Object.values(assets))
    ]) {
      image.addEventListener("load", requestDraw, { once: true });
    }

    return {
      setState(nextState) {
        canvas.dataset.state = nextState;
        if (nextState === targetState) return;
        const now = performance.now();
        const elapsed = Math.max(0, (now - transitionStartedAt) / 1000);
        const visibleState = previousState !== targetState
          ? transitionVisualState(
            previousState,
            targetState,
            transitionAmount(now)
          )
          : targetState;
        fromPose = sampleCurrent(now);
        previousStateElapsedAtTransition = visibleState === targetState
          ? elapsed
          : previousStateElapsedAtTransition + elapsed;
        previousState = visibleState;
        targetState = nextState;
        transitionStartedAt = now;
        requestDraw();
      },
      setCharacter(nextCharacter) {
        const resolved = nextCharacter === "cat" || animePetCharacters.includes(nextCharacter)
          ? nextCharacter
          : "cat";
        if (resolved === character) return;
        character = resolved;
        previousState = targetState;
        transitionStartedAt = performance.now();
        requestDraw();
      },
      setFacesLeft(nextFacesLeft) {
        const resolved = Boolean(nextFacesLeft);
        if (resolved === facesLeft) return;
        facesLeft = resolved;
        requestDraw();
      },
      setVisible(nextVisible) {
        visible = Boolean(nextVisible);
        canvas.hidden = !visible;
        if (!visible && frame) {
          cancelAnimationFrame(frame);
          frame = null;
        } else {
          requestDraw();
        }
      },
      renderFrameForQA(nextState, elapsedSeconds) {
        if (frame) cancelAnimationFrame(frame);
        frame = null;
        const state = typeof nextState === "string" ? nextState : "walk_right";
        const elapsed = Math.max(0, Number(elapsedSeconds) || 0);
        canvas.dataset.state = state;
        drawCat(
          context,
          samplePose(state, elapsed),
          state,
          state,
          1,
          elapsed,
          elapsed,
          character,
          facesLeft
        );
      },
      renderFootstepImpactForQA(ageSeconds) {
        if (frame) cancelAnimationFrame(frame);
        frame = null;
        const age = Math.max(0, Number(ageSeconds) || 0);
        const impact = Math.max(0, Math.min(1, 1 - age / .14));
        const expansion = .72 + Math.min(1, age / .20) * .28;
        context.clearRect(0, 0, 480, 288);
        context.save();
        drawFootstepDent(context, character, 210, 249, expansion, impact);
        drawFootstepCracks(context, 210, 248, 18, expansion);
        context.restore();
      }
    };
  }

  window.CodexCatRig = Object.freeze({ create });
})();
