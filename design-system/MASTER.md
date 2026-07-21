# Codex-Pulse Design System

> Source of truth for visual language. Inspired by [ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) styles: **Glassmorphism**, **Liquid Glass**, **Spatial UI (visionOS)**, **Bento Grid**. Product type: Developer Tool / macOS Menu Bar Utility.

## Positioning

Codex-Pulse lives in the macOS menu bar and on the desktop. The UI should feel like a native **Control Center / Weather / Battery** panel: frosted glass over a living desktop, not a dark SaaS dashboard.

## Style recipe

| Layer | Choice | Why |
|-------|--------|-----|
| Primary style | Glassmorphism + Liquid Glass | Menu bar popovers and widgets are glass-first on modern macOS |
| Layout | Bento for dashboard | Modular status tiles match Apple widget language |
| Product palette | Developer Tool (muted) | Status green + system blue; avoid AI purple/pink gradients |
| Anti-patterns | Neon cyberpunk, harsh shadows, emoji icons, 500ms+ flashy motion | Breaks native feel and accessibility |

## Color tokens

```
--pulse-green:     #30D158   /* healthy / idle */
--pulse-blue:      #0A84FF   /* running */
--pulse-yellow:    #FFD60A   /* caution */
--pulse-orange:    #FF9F0A   /* warning */
--pulse-red:       #FF453A   /* critical */

--glass-light:     rgba(255, 255, 255, 0.52)
--glass-light-2:   rgba(255, 255, 255, 0.28)
--glass-dark:      rgba(28, 28, 30, 0.42)
--glass-dark-2:    rgba(28, 28, 30, 0.28)
--glass-border:    rgba(255, 255, 255, 0.38)
--glass-border-d:  rgba(255, 255, 255, 0.14)
--glass-highlight: rgba(255, 255, 255, 0.55)
--glass-shadow:    0 18px 48px rgba(0, 0, 0, 0.22),
                   0 2px 8px rgba(0, 0, 0, 0.08),
                   inset 0 1px 0 rgba(255, 255, 255, 0.45)

--text-primary:    #1D1D1F   /* light mode on glass */
--text-secondary:  rgba(29, 29, 31, 0.62)
--text-on-dark:    #F5F5F7
--text-on-dark-2:  rgba(245, 245, 247, 0.68)
```

Desktop wallpaper behind glass must stay **vibrant but soft** so frost reads correctly (sky blue, soft teal, warm peach mesh). Do not use flat pure black or pure white behind glass.

## Glass material (CSS)

```css
.glass {
  background: linear-gradient(
    155deg,
    rgba(255, 255, 255, 0.58) 0%,
    rgba(255, 255, 255, 0.28) 48%,
    rgba(255, 255, 255, 0.22) 100%
  );
  backdrop-filter: blur(40px) saturate(180%);
  -webkit-backdrop-filter: blur(40px) saturate(180%);
  border: 1px solid rgba(255, 255, 255, 0.42);
  border-radius: 18px;
  box-shadow:
    0 18px 48px rgba(0, 0, 0, 0.18),
    0 2px 8px rgba(0, 0, 0, 0.06),
    inset 0 1px 0 rgba(255, 255, 255, 0.55),
    inset 0 -1px 0 rgba(255, 255, 255, 0.08);
}
```

Dark glass (menu bar night):

```css
.glass-dark {
  background: linear-gradient(
    160deg,
    rgba(40, 42, 48, 0.72) 0%,
    rgba(22, 24, 28, 0.55) 100%
  );
  backdrop-filter: blur(40px) saturate(170%);
  border: 1px solid rgba(255, 255, 255, 0.14);
  box-shadow:
    0 20px 50px rgba(0, 0, 0, 0.45),
    inset 0 1px 0 rgba(255, 255, 255, 0.12);
}
```

## Glass material (SwiftUI)

```swift
// Menu bar panel
.background {
  RoundedRectangle(cornerRadius: 16, style: .continuous)
    .fill(.ultraThinMaterial)
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(
          LinearGradient(
            colors: [
              .white.opacity(0.45),
              .white.opacity(0.12),
              .white.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
    }
    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
}

// Dashboard cards
.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

// macOS 15+ prefer:
// .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))  // when available
```

## Typography

| Role | Face | Notes |
|------|------|-------|
| UI / body | SF Pro Text (system) / Inter | 13–15px body, 11–12px captions |
| Numbers | SF Pro Rounded / tabular mono | Percent, tokens, countdown |
| Brand wordmark | SF Pro Display medium | “Codex-Pulse” only |

Never use decorative serif display fonts for this product.

## Spacing & radius

```
--radius-sm: 10px
--radius-md: 14px
--radius-lg: 18px   /* popover */
--radius-xl: 24px   /* widget / bento */
--space-1: 4px
--space-2: 8px
--space-3: 12px
--space-4: 16px
--space-5: 20px
--space-6: 24px
```

Menu bar popover width: **320–340px**. Widget medium: **~340×158**.

## Motion

- Micro: 160–220ms ease
- Panel open: 200–280ms
- Progress bar fill: 500–600ms ease-out
- Respect `prefers-reduced-motion`
- Max 1–2 ambient motions (soft wallpaper drift only)

## Signature element

**Frosted progress “liquid bar”** — capsule track with glass edge + status-colored fill that soft-glows. This is the one memorable control; everything else stays quiet.

## Checklist (from ui-ux-pro-max)

- [x] Backdrop blur 20–40px + saturate
- [x] Translucent glass 15–55% depending on light/dark
- [x] 1px light border + inner highlight
- [x] Vibrant desktop backdrop (not flat)
- [x] Text contrast ≥ 4.5:1 on glass
- [x] No emoji icons; use SF Symbols / SVG
- [x] Hover / focus states 150–300ms
- [x] Reduced motion supported
