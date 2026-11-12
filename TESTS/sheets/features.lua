-- TESTS/sheets/features.lua -- the functionalities of runtime-analysis.nvim as its user meets them; `testing sheets
-- report` says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet
-- that names an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/FEATURES/ (README.md and its pages), docs/commands.md and
-- ALL/manual-test-checklists/runtime-analysis.md.
return {
  {
    id = "runtime-analysis.requests",
    title = "Send a request from a .http buffer: response, yank, cancel, history, {{var}} environments, curl",
    surface = {
      "command:RA request",
      "command:RA send",
      "command:RARequest",
      "command:RASend",
      "command:RA yank",
      "command:RA cancel",
      "command:RA history",
      "command:RA history clear",
      "command:RA env",
      "command:RA import",
      "command:RA export",
    },
    docs = "docs/FEATURES/REQUESTS.md",
  },
  {
    id = "runtime-analysis.request-bodies",
    title = "GraphQL and multipart bodies, the Auth: shorthand and a # @expect status smoke test in a request",
    docs = "docs/FEATURES/REQUESTS.md",
  },
  {
    id = "runtime-analysis.request-transcript",
    title = ":RA transcript on keeps a Markdown protocol of the sends, without headers or bodies, for mdview.nvim",
    docs = "docs/commands.md",
  },
  {
    id = "runtime-analysis.telemetry",
    title = "Opt-in call counting for a Lua plugin: start, stop and the status of a namespace through :RATelemetry",
    surface = {
      "command:RATelemetry",
      "command:RATelemetryStartAll",
      "command:RATelemetryStopAll",
      "command:RATelemetryResetAll",
      "command:RATelemetrySetupAll",
      "command:RATelemetrySetupAllFull",
    },
    docs = "docs/FEATURES/TELEMETRY.md",
  },
  {
    id = "runtime-analysis.telemetry-reports",
    title = "The telemetry reports on recorded data: call trees, compare over time windows, cost and the browser report",
    surface = { "command:RATelemetry" },
    docs = "docs/FEATURES/TELEMETRY.md",
  },
  {
    id = "runtime-analysis.telemetry-offline",
    title = "A namespace is read straight off disk with no live instance, headless for CI or a cron job",
    docs = "docs/FEATURES/TELEMETRY.md",
  },
  {
    id = "runtime-analysis.loaded",
    title = "What package.loaded holds right now, with named snapshots a later session can still read",
    surface = { "command:RA loaded snapshot", "command:RA loaded snapshots" },
    docs = "docs/FEATURES/LOADED.md",
  },
  {
    id = "runtime-analysis.startup",
    title = "Stall detection and startup attribution: a block shows up whatever caused it, with lazy's load reason",
    surface = {
      "command:RA startup start",
      "command:RA startup watch",
      "command:RA startup report",
      "command:RA startup probe",
      "command:RA startup profile",
    },
    docs = "docs/FEATURES/STARTUP.md",
  },
  {
    id = "runtime-analysis.inspect",
    title = "Ask the running session: :RA inspect walks a module, :RA provenance names who wrapped a function",
    surface = { "command:RA inspect", "command:RA provenance" },
    docs = "docs/FEATURES/README.md",
  },
  {
    id = "runtime-analysis.usage",
    title = ":RA usage counts which of the user's own keymaps and typed commands are actually pressed",
    surface = { "command:RA usage", "command:RA usage start", "command:RA usage stop" },
    docs = "docs/commands.md",
  },
  {
    id = "runtime-analysis.bench",
    title = "Time candidate functions against each other",
    docs = "docs/FEATURES/BENCH.md",
  },
  {
    id = "runtime-analysis.docmap-join",
    title = "docmap.nvim hands a route over as a request buffer and joins its static analysis with these counts",
    surface = { "api:runtime-analysis.open_request" },
    docs = "docs/api.md",
  },
}
