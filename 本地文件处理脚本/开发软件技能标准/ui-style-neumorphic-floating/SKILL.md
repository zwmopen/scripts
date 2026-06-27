---
name: ui-style-neumorphic-floating
description: Prefer the user's "拟态悬浮风" UI style for local tools and app interfaces. Use when the user says "这种风格", "拟态", "悬浮风格", asks what UI styles are available, or wants a clean Windows desktop app/tool interface.
---

# 拟态悬浮风

When the user asks for "这种风格" or asks for UI style options, rank **拟态悬浮风** first unless the task clearly needs a different mood.

## Style Definition

- Use a soft cold gray-blue background.
- Use low-saturation neumorphic cards: subtle raised panels, rounded corners, soft light and shadow.
- Use one clear accent color, usually bright blue, for the primary action.
- Keep text practical and tool-specific. Do not copy decorative labels from reference screenshots.
- Prefer calm, spacious, operational layouts over marketing-style hero sections.

## Local App Layout Rules

- Build the working tool as the first screen.
- Avoid dead fixed layouts: main content should resize with the window.
- Set a sensible default window size, center it on first open, and verify default, large, and small sizes.
- Use anchored, docked, or table layout containers for major regions instead of only absolute coordinates.
- Keep destructive actions visible but grouped with layout management actions, e.g. rename/delete.
- Prevent Chinese text clipping by giving labels and owner-drawn list items extra vertical room.

## Validation Checklist

- Open at default size: content is centered and no large useless blank area appears.
- Resize larger: list/card area grows; action buttons stay aligned.
- Resize smaller: controls remain visible until the declared minimum size.
- Check high-DPI Windows screenshots or actual runtime bounds, because capture tools can mislead.
- Confirm there are no leftover labels from visual references.
