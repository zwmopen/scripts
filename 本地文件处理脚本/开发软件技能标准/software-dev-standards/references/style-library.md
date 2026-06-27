# 风格库

This file stores reusable UI styles for software, scripts, and local tools. When a user says "这种风格" without naming a different style, prefer style 1.

## 1. 拟态悬浮风

Use for local desktop tools, workflow launchers, batch processors, small internal apps, and calm productivity utilities.

### Keywords

- 拟态悬浮风
- 拟态
- 悬浮风格
- 玻璃感但不要透明混乱
- 高级一点的小工具界面

### Visual Direction

- Background: cold gray-blue, soft and low saturation.
- Surfaces: raised cards with subtle highlight and shadow, not hard bordered boxes.
- Corners: rounded but not childish; usually 14-24 px for app panels and 8-14 px for buttons.
- Accent: one clear blue primary action; secondary actions use quiet gray-blue.
- Density: practical and calm; enough spacing for Chinese text, but not a marketing landing page.
- Typography: clear system font, medium weight for titles, no tiny crowded labels.

### Layout Pattern

- Use a two-zone productivity layout when useful:
  - Main content/list/preview area grows with the window.
  - Action area stays aligned and readable.
- Use docked, anchored, grid, or table layout containers.
- Avoid absolute-only layouts that freeze when the window resizes.
- Avoid large empty areas on default launch.
- Add minimum window size only after confirming the UI still works at that size.

### Component Rules

- Primary button: blue, raised, clear label.
- Secondary button: light raised surface, muted text.
- Destructive action: visible but separated from primary workflow.
- Cards/list items: enough vertical room for Chinese title + metadata.
- Toast/tip: centered or easy to notice, short duration, clean color, no blocking modal unless confirmation is needed.

### Avoid

- Copying labels or domain words from a reference screenshot.
- Random colorful accents everywhere.
- Heavy black shadows, hard outlines, neon gradients, or purple decorative blobs.
- Tiny text that looks "technical" but is hard to read.
- UI that looks good in one screenshot but breaks when resized.

### Validation

- Open default size: centered, no clipping, no pointless blank regions.
- Resize larger: content actually expands.
- Resize smaller: controls remain usable until minimum size.
- Test with Chinese text and timestamps.
- Test the packaged exe, not only the source build.

## Future Slots

Add new styles below with the same structure:

- Use case
- Keywords
- Visual direction
- Layout pattern
- Component rules
- Avoid
- Validation
