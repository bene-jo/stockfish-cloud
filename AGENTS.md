# AGENTS.md

## Project

`stockfish-cloud` is a product experiment for running Stockfish chess analysis
on Hetzner Cloud servers so the user's Mac stays free.

The repo should contain:

- CLI/server automation for Hetzner lifecycle and remote jobs.
- Docker worker image for Stockfish.
- Native macOS GUI app for managing servers, jobs, live analysis, results, and
  costs.

Keep human-facing usage short in `README.md`. Keep durable project context,
decisions, constraints, and implementation notes in this file.

## Handoff Snapshot

Start here when taking over without the chat context:

1. Read this `AGENTS.md`, then `README.md`, then `docs/worker-image.md`.
   Also read `docs/mac-app-ui-reference.md` before building the macOS app UI.
2. Run `git status --short --untracked-files=all`; the repo should normally be
   clean on `main` unless the current thread is actively editing files.
3. Run `hcloud server list` before and after any remote test. There should be no
   running servers unless the user intentionally started one.
4. Do not assume `ccx43` works yet. The current Hetzner dedicated-core project
   limit blocks it.
5. Prefer the prebuilt-image path over building Stockfish on every server once
   the GitHub repo and GHCR package exist.

Recommended next implementation sequence:

1. Scaffold the native macOS app under `mac/` using the available macOS skills.

Open product requirement to preserve: the macOS app must show live analysis,
similar in spirit to Lichess, with current eval, current depth/nps, and the top
N lines updating while a job runs.

## Current State

- Hetzner CLI context: `stockfish-cloud`.
- Hetzner SSH key name: `macbook-stockfish-cloud`.
- Confirmed working server types in `fsn1`: `ccx13`, `ccx33`.
- Current Hetzner account limit allows `ccx33` but blocks `ccx43` with
  `dedicated core limit exceeded`.
- Default reusable server name: `stockfish-cloud`.
- GitHub repo: `https://github.com/bene-jo/stockfish-cloud`.
- Published worker image:
  `ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`.
- First worker-image workflow run succeeded on 2026-06-07:
  `https://github.com/bene-jo/stockfish-cloud/actions/runs/27076443609`.
- GitHub Actions were updated to current Node.js 24-compatible major versions
  on 2026-06-07 after GitHub warned that older Node.js 20 actions are being
  phased out. The updated worker-image run succeeded:
  `https://github.com/bene-jo/stockfish-cloud/actions/runs/27076587960`.
- GHCR image pull was verified on a fresh `ccx13` server with
  `start --skip-build --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`.
- Analysis jobs should reuse a warm server and must not delete it automatically;
  users often want to run several jobs back to back.
- `analyze-fen --stream` emits JSONL `analysis_state` snapshots. The app should
  persist the latest snapshot as state; the final snapshot has
  `status: "completed"` with `bestmove` and `ponder` set.
- `analyze-position` is the app-facing analysis command. It defaults to
  streamed JSONL, depth `40`, and `3` lines.
- `stop-position --position-id ...` stops the named remote Docker container for
  a running analysis. Stop is an action, not a separate position state; terminal
  stream snapshots still use `status: "completed"`.
- `status --json` returns app-facing server status, uptime, hourly rate, and
  estimated live cost.
- App-facing backend commands were verified on a temporary `ccx13` server on
  2026-06-07:
  - `status --json` returned running status, uptime, hourly rate, and live cost.
  - `analyze-position --position-id backend-verify-1 --depth 40 --lines 3`
    streamed `positionId`, `currentDepth`, `targetDepth`, and top lines.
  - `stop-position --position-id backend-verify-1 --json` stopped the named
    remote container; the terminal stream snapshot used `status: "completed"`
    with `currentDepth: 25` and `targetDepth: 40`.
  - The temporary `stockfish-cloud-backend-verify` server was deleted and
    `hcloud server list` was empty afterward.
- Servers should still be deleted explicitly when no longer needed.
- No separate product-direction markdown file is used; product direction belongs
  in this `AGENTS.md`.

Always verify no server was left running after tests:

```bash
hcloud server list
```

## Product Direction

Working name: Stockfish Cloud.

Build a small native macOS app for running remote Stockfish analysis jobs on
temporary Hetzner Cloud servers. The app should make remote compute feel as
simple as pasting positions into a native queue, while keeping local Mac
resources free.

All user-facing UI text should be in English.

Primary user flow:

1. Paste one or more FENs.
2. Choose analysis parameters.
3. Start a Hetzner server and keep it warm while useful.
4. Start one or more remote Stockfish position analyses.
5. Watch live analysis and final results in a history list.
6. Stop individual jobs or explicitly delete the whole server when done.

The macOS app should feel like a native desktop job console, not a marketing
page. The core UX is operational and dense enough for repeated use.

Expected controls:

- Server type selector: `ccx13`, `ccx33`, later `ccx43`.
- Location selector, default `fsn1`.
- Threads per job.
- Hash size.
- MultiPV / number of lines.
- Depth or movetime limit.
- Max server runtime / cost guardrail.
- Start server, stop server, delete server.
- Start, stop, retry, and delete positions.

Expected views:

- Server status: offline, creating, ready, running jobs, deleting, error.
- Live cost panel showing current server runtime, current server estimated cost,
  hourly rate, and accumulated session cost.
- Positions list with each FEN or opening name, status, depth, and elapsed time.
- Live analysis view, similar in spirit to the Lichess analysis UI:
  current eval, current depth, nodes/sec, and the top N principal variations
  updating while the engine is still running.
- Result detail with best move, evaluation, principal variations, nodes/sec,
  elapsed time, and raw UCI log if needed.

Live analysis is a product requirement, not just a nice-to-have. The worker/CLI
streams UCI `info` lines as structured `analysis_state` JSONL snapshots so the
app can show the current top lines and eval while analysis is still running.

## Architecture Direction

Start simple:

```text
macOS app
  -> invokes local CLI or helper
  -> hcloud creates or finds a reusable server
  -> SSH runs Docker worker
  -> worker runs Stockfish
  -> live state snapshots return as JSONL
  -> app persists local history
```

Do not build a public web API yet. A local-only control app avoids exposing
secrets and keeps the first version lean.

The current CLI has a first reusable-server analysis shape:

```bash
./bin/stockfish-cloud start --server-type ccx33
./bin/stockfish-cloud analyze-fen --server stockfish-cloud --fen "<fen>" --multipv 3 --movetime 10000
./bin/stockfish-cloud analyze-position --server stockfish-cloud --position-id position-1 --fen "<fen>"
./bin/stockfish-cloud stop-position --server stockfish-cloud --position-id position-1
./bin/stockfish-cloud delete --server stockfish-cloud
```

`analyze-fen` returns one final structured JSON result by default for manual CLI
use and debugging. With `--stream`, it emits JSONL `analysis_state` snapshots
instead. Each running snapshot contains the latest parsed top lines; the final
snapshot uses the same shape with `status: "completed"`, `bestmove`, and
`ponder`.

`analyze-position` is the app-facing wrapper around `analyze-fen`. It defaults
to `--stream`, `--depth 40`, `--lines 3`, and a generated `positionId` if the
caller does not provide one. When a `positionId` is present, the remote Docker
container is named `stockfish-position-<positionId>` so `stop-position` can stop
it from another app action.

The UI `+` button next to depth should increase target depth in steps of `5`.
Backend support is intentionally simple: a running position exposes
`currentDepth` and `targetDepth` in stream snapshots, and a higher target depth
can be run for the same `positionId` when the user wants more depth. If true
in-process depth extension becomes important later, add a small command channel
instead of building a public API.

The faster prebuilt-image start path is:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --skip-build
```

The GitHub Actions workflow is active on `main`.

## Worker Image

The fallback smoke-test flow builds the repo's `docker/` worker image on the
temporary server. This proves the lifecycle works, but is too slow and noisy for
production use.

The repo has a prebuilt-image path:

- `.github/workflows/worker-image.yml` publishes to GitHub Container Registry.
- `docs/worker-image.md` documents the image name and usage.
- `start --skip-build --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`
  pulls the image on the Hetzner server instead of compiling Stockfish there.

## State Model

Server lifecycle:

```text
offline -> creating -> booting -> ready -> running -> deleting -> offline
                            \-> error
```

Position lifecycle:

```text
starting -> running -> completed
                  \-> failed
```

The app should treat server deletion as the strongest safety action. If anything
gets weird, deleting the server is the cost-control escape hatch.

Cost state:

```text
server hourly rate + server start time -> live server cost
completed server runs -> accumulated session cost
job runtime + assigned server run -> per-job cost estimate
```

Costs should be labeled as estimates because Hetzner billing and rounding are
provider-side. The UI should still make the estimated spend visible before,
during, and after a server run.

## Benchmarks And Validation

Validated on 2026-06-07:

- `ccx13`, 2 threads, depth 10: `1,512,759 nodes/sec`.
- `ccx33`, 8 threads, depth 10: `6,921,528 nodes/sec`.
- Remote FEN analysis returned structured JSON with `bestmove`, `ponder`,
  `elapsedMs`, MultiPV lines, scores, nodes, nps, and raw UCI lines.
- Start-position test on `ccx13`, 2 threads, 1 second movetime:
  `bestmove e2e4`, `ponder e7e5`, `elapsedMs 1306`, `nps 1,382,620`.
- Prebuilt GHCR image path validated on `ccx13`, 2 threads, 1 second movetime,
  MultiPV 3, streamed JSONL: final state had `bestmove e2e4`, `ponder e7e5`,
  `elapsedMs 1345`, depth 19 on the top line, and about `1,452,099 nps`.
  The temporary `stockfish-cloud-verify` server was deleted and
  `hcloud server list` was empty afterward.
- Multi-stage Dockerfile smoke-tested on `ccx13` via `bench`, 2 threads,
  depth 1. The runtime image successfully ran `/usr/local/bin/stockfish` with
  the embedded NNUE network, then the temporary server auto-deleted.

## Cost Notes

Hetzner bills while the server object exists. Delete servers when done; stopping
is not the intended cost-control action.

API-confirmed Germany / Finland hourly prices including VAT:

- `ccx13`: about `0.0305 EUR/h`.
- `ccx33`: about `0.1191 EUR/h`.
- `ccx43`: about `0.238357 EUR/h`.

Cost UX should be quiet but always visible while a server exists:

- Current server, for example `ccx33`.
- Hourly rate, for example `0.1191 EUR/h`.
- Runtime, for example `12m 34s`.
- Estimated current run cost, for example `0.025 EUR`.
- Accumulated session cost, for example `0.18 EUR`.
- Max runtime / max cost controls before starting a server.

If a cost guardrail is reached, the app should stop accepting new jobs and offer
a clear delete-server action.

## Important Constraints

- Hetzner bills cloud servers while the server object exists. Analysis should
  not auto-delete after each job, but the UI must make manual deletion obvious.
- Current account limit allows `ccx33` but not `ccx43`.
- API tokens must not be stored casually in repo files. macOS Keychain is the
  likely place for app storage.
- The app should make costs visible before starting a job, while a server is
  running, and in accumulated session/history summaries.
- Raw UCI output is useful for debugging, but the user-facing result should be
  structured.

## Repository Conventions

- Keep the implementation lean and convention-first.
- Prefer shell-first automation for the CLI/worker until a native macOS app
  needs direct integration.
- Keep server lifecycle explicit: `start` prepares a reusable server,
  `analyze-fen` runs against an existing server, and `delete` removes the server.
- Do not commit or expose Hetzner API tokens.
- Store app secrets in macOS Keychain when the GUI is built.
- Keep user-facing UI text in English.
- Keep `.DS_Store` irrelevant; do not track or worry about it.

## macOS App Skills

The macOS plugin skills are available under:

```text
/Users/bene/.codex/plugins/cache/openai-curated/build-macos-apps/3f0def1b/skills/
```

Use these when building the app:

- `swiftpm-macos`
- `swiftui-patterns`
- `build-run-debug`
- `appkit-interop` when SwiftUI needs native AppKit bridging
- `signing-entitlements` and `packaging-notarization` for distribution work

Relevant skill guidance:

- For non-trivial macOS apps, use a multi-file structure from the start.
- Prefer SwiftPM for package-first macOS work when practical.
- Create `script/build_and_run.sh` and `.codex/environments/environment.toml`
  when scaffolding the app so the Codex Run button works.
- Use system-adaptive SwiftUI colors/materials and desktop patterns.

## macOS UI Reference

Current UI reference:

- `docs/mac-app-ui-reference.md`
- `docs/assets/mac-app-ui-reference-minimal.png`

Treat the image as a wireframe-level reference for information hierarchy,
layout, and product direction, not as exact design guidance. Implement the app
with standard SwiftUI controls and native macOS behavior.

Key UI direction captured by the reference:

- Minimal two-pane app.
- Left pane: compact server panel, `New Position` form, then `Positions`.
- Server panel only needs status, uptime, live cost, and either start or delete.
- Position creation takes FEN, max depth default `40`, number of lines, and
  `Start Analysis`.
- Positions list should show running and completed positions together without
  completed badges or queue language.
- Right pane: selected position details only; no board in the first version.
- Focus details on depth, time running, nodes/sec, and top lines with evals.
- Add a small `+` button next to depth to increase target depth by `5`.
- Do not model user-stopped positions as a separate UI state in the first
  version; use `currentDepth` / `targetDepth` to show whether the target was
  reached.
- Do not include redundant parameters, raw engine output, standalone eval, or
  best-move blocks in the initial UI.

## Next Steps

1. Scaffold the native macOS app under `mac/`.
