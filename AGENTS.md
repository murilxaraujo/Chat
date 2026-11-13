# Chat Package Instructions

The workspace-level `../AGENTS.md` applies to this repository. Chat is the
open-source multiplatform agentic chat presentation package.

## Package boundaries

- Own reusable chat presentation, message/input components, customization
  points, and platform-specific interaction that belongs to the chat UI.
- Keep Kernel-specific concepts such as model-provider selection, tool
  authorization, ACP/workspace execution, app navigation, and SwiftData
  persistence in `../Kernel/` or `../HarnessKit/` as appropriate.
- Keep the package's message and UI APIs presentation-focused. Do not make the
  chat package responsible for calling a model or deciding whether a tool may
  run.
- Preserve the package's open-source license, supported platforms, and public
  customization APIs. Treat uncommitted source changes as intentional work and
  do not replace them with the copy under `Kernel/Vendor/Chat`.

## SwiftUI and concurrency

- Keep macOS and iOS experiences native. Share implementation only where
  interaction and behavior are genuinely common; use platform-specific
  composition where input or navigation differs.
- Use modern SwiftUI data flow and stable view identity. Keep view state local
  where possible and avoid needless updates during streaming.
- Inspect `Package.swift` for the actual Swift language mode, platform
  availability, and concurrency settings before making changes. Use explicit
  isolation and cancellation-safe tasks; do not use unsafe concurrency
  annotations as a shortcut.
- Before adopting or extending Apple APIs, use Xcode MCP
  `DocumentationSearch` and verify availability for the package's declared
  platforms.

## Tests and offline work

- Use deterministic Swift Testing tests. Do not require live services, account
  credentials, or network access for unit tests.
- Do not add package dependencies or run package resolution while the workspace
  is offline. Preserve the existing lockfile and local edits.
- Run focused package tests only when all required dependencies are already
  cached; report clearly if offline dependency availability blocks validation.
