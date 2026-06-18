# Pointer

**Your cursor, but it can think.**

Pointer is a native macOS app that turns any spot on your screen into something you can ask about — and act on. Hold **Option** and right-click anywhere, and a little panel pops up that already understands what you clicked: the button, the paragraph, the form field, the chart, the error message. From there you can ask a question, get an explanation, or just say "fill this out for me" and watch it happen.

It's the assistant I always wanted: not a chat window in a separate app that I have to copy-paste into, but something that lives *on top of everything* and meets me where I'm already working.

---

## Demo

▶️ **Watch the walkthrough:** 

https://github.com/user-attachments/assets/94304ff5-ddf2-4a03-a595-af43da8ebf81

---

## What it actually does

A few things it can do today:

- **Explain anything under your cursor.** Option+right-click a confusing error, a dense legal clause, a math expression, or a UI you've never seen, and ask "what is this?" Pointer reads the actual on-screen element (not just a screenshot) and answers in a clean little panel.
- **Do things for you.** Ask it to click a button, fill a form with your info, or walk through a multi-step flow across apps ("summarize this PDF and paste it into the email below"). It uses the accessibility layer of macOS to click and type like a careful human would.
- **Find stuff nearby.** "Find me a restaurant" uses your location to actually search places around you, then shows the results as tappable cards.
- **Answer over your own documents.** A "Drawer" feature lets you drop in files, screenshots, text, and links to build a little project workspace, then ask questions across all of it — with the search and embeddings running **on your own machine**, so the raw content never leaves until you ask something.
- **Talk to it.** Tap to record a question instead of typing.

The whole thing is **opt-in by gesture**. Nothing about your screen leaves your computer until *you* deliberately trigger it. No always-on recording, no background uploads.

---

## Why I think it matters

Most "AI assistants" make you leave what you're doing, describe your problem in words, and paste in context by hand. But the context is *right there on your screen* — the computer already knows what you're looking at. Pointer's bet is that the most useful place for an assistant is directly on top of your work, with the ability to both **understand** the screen and **act** on it safely.

It's also a real exercise in doing this *responsibly*: an agent that can move your mouse and type is powerful and a little scary, so a big part of the project is the guardrails — confirmation prompts, a tiered permission model for risky actions, automatic redaction of password fields, and a global "panic" key that instantly kills anything in progress.

---

## How it's built

Pointer is two pieces that talk over a streaming connection:

### The macOS app (Swift 6, SwiftUI + AppKit)

This is where all the "magic on top of your screen" happens:

- **Triggers** — a global Option+right-click listener (a low-level event tap) and a keyboard shortcut, so Pointer can be summoned from anywhere without stealing focus from your current app.
- **Context capture** — reads the element under your cursor through the macOS **Accessibility API** (its role, title, value, selection) and grabs a small screenshot region with **ScreenCaptureKit**. Password fields are detected and redacted before anything is sent.
- **The panel** — a floating, non-activating window that figures out which quick actions make sense for what you clicked (a code editor gets different options than a form or an image).
- **Actions** — when the AI decides to *do* something, the app carries it out, preferring precise accessibility actions ("press this specific button") over blind coordinate clicks, and falling back to simulated input or AppleScript only when needed.
- **On-device retrieval** — the Drawer feature chunks and embeds your documents locally using Apple's natural-language framework, so only the most relevant snippets are ever sent to the model.

### The backend (TypeScript, Hono, Google Gemini)

A small server that orchestrates the actual reasoning:

- Runs a **multi-turn agent loop**: the model can call tools, the app executes them, results stream back, and the loop continues until the task is done.
- **Streams** every token back to the app over Server-Sent Events so answers appear as they're written.
- Uses a **dual strategy** depending on the task: a fast text model for questions and accessibility-driven actions, and Google's **Computer Use** vision model (which "sees" the screen on a coordinate grid) for trickier visual automation.
- Enforces **safety server-side**: every tool call is validated and sorted into safe / automation / destructive tiers, dangerous inputs are blocked, and sensitive data is stripped.

There's a shared schema describing all the tools so the client and server never disagree about what's possible, and both sides have test suites.

---

## A few of the fun engineering problems

- Making an agent that can act on *any* app without being sandboxed, while keeping it safe with layered confirmation and redaction.
- Streaming partial answers smoothly while the model is still "thinking" — including a nasty bug where Gemini emits its tool calls in an early stream chunk, so the parser had to reassemble calls across the whole stream instead of trusting the last frame.
- Wrangling **Swift 6 strict concurrency** so the network agent loop runs off the main thread without ever touching the UI from the wrong place (and tracking down a SwiftUI layout-reentrancy crash that came from resizing the panel mid-update).
- Deciding, per request, whether to solve a task with the *semantic* accessibility tree or with *vision* — they have very different speed and reliability tradeoffs.

---

## Project status

This is a personal project and a work in progress — built to explore what a genuinely useful, on-screen AI agent could feel like. Expect rough edges. It's being built in shippable phases (panel → drawers → safe actions → full automation → ambient hints); see [`docs/architecture.md`](docs/architecture.md) for the detailed plan.

---

## Try it yourself

### 1. Backend

```bash
cd backend
pnpm install
cp .env.example .env     # add your GEMINI_API_KEY (free from Google AI Studio)
pnpm dev                 # starts on http://localhost:8787
```

> No API key? The backend automatically falls back to a deterministic **mock** provider, which is great for poking at the app without spending credits.

### 2. macOS app

The Xcode project is generated from `mac/project.yml` via [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd mac
xcodegen generate
open Pointer.xcodeproj
```

Then **Product → Run**. On first launch, Pointer walks you through granting Accessibility, Screen Recording, Input Monitoring, and (optionally) Microphone and Location permissions. Once you're set up, just **Option + right-click anything**.

---

## Repository layout

| Path                                | What's inside                                       |
| ----------------------------------- | --------------------------------------------------- |
| [`mac/`](mac/)                      | The macOS app (Swift 6 / SwiftUI / AppKit)          |
| [`backend/`](backend/)             | The orchestration server (TypeScript + Hono + Gemini) |
| [`shared/schema/`](shared/schema/) | The tool/action schema shared by client and server  |
| [`docs/`](docs/)                    | Architecture, permissions, and threat-model notes   |

Each subfolder has its own README with more detail.

## License

MIT — see [LICENSE](LICENSE).
