---
description: "Visual debug for inspecting layout and styling issues in TerminalRSS views"
---

# Visual Debug

When the user runs /look, take a screenshot of the running app and inspect for layout/styling issues.

## Step 1: Identify the View

Ask the user which view to inspect:
- Feed list sidebar
- Article list
- Article detail / reader view
- Full app window

## Step 2: Screenshot

Take a screenshot of the running app or the specific view.

## Step 3: Inspect

Check for:
- **Terminal aesthetic consistency** — monospace font, dark background, proper contrast
- **Markdown rendering** — headings, bold, italic, code blocks rendering correctly
- **Spacing** — consistent padding, no cramped elements
- **Alignment** — left edges aligned, consistent indentation
- **Text readability** — font size appropriate, line height comfortable
- **Empty states** — helpful messages when no feeds/articles
- **Visual hierarchy** — clear distinction between feed names, article titles, body text

## Step 4: Report

List specific issues with view/element references. Flag anything that breaks the terminal aesthetic.

## Rules

- Always take a screenshot before reading code
- Report specific elements, not vague observations
