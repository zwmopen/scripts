---
name: software-dev-standards
description: Reusable software development standards for local desktop tools and small apps, including UI style selection, layout robustness, Chinese text handling, packaging, validation, and shareable delivery. Use when the user asks to build, redesign, polish, package, standardize, or review a software tool/app, or asks for a style library, "这种风格", "拟态悬浮风", or reusable development methods.
---

# 软件开发标准

Use this skill to turn one-off app work into repeatable product standards.

## Working Rule

- Build the usable tool first; avoid marketing-page layouts unless explicitly requested.
- Preserve existing working behavior before redesigning visuals.
- Prefer durable layout systems over fixed coordinates: dock, anchor, table/grid, min/max sizes, scroll regions.
- Treat Windows high-DPI, Chinese text clipping, resize behavior, and packaged exe testing as required quality gates.
- When the user asks for UI style options or says "这种风格", load `references/style-library.md` and rank "拟态悬浮风" first unless the product clearly calls for another style.

## App Quality Checklist

- Default launch: window is centered, usable, and has no large meaningless blank area.
- Resize larger: main content grows naturally; action buttons stay aligned.
- Resize smaller: controls remain visible until the declared minimum size; no overlap or clipping.
- Chinese UI: list items, buttons, labels, and timestamps have enough height and width.
- Runtime behavior: existing windows/files/data are reused when possible; repeated actions should not create duplicate noise.
- Delivery: exe, source, README or usage notes, and any templates/assets are kept together.
- Validation: build the app, open the packaged exe, and test the core workflow before calling it done.

## References

- `references/style-library.md`: reusable UI style library, starting with the user's preferred "拟态悬浮风".
