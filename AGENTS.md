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
2. Run `git status --short --untracked-files=all`; the repo is currently a new
   local Git repo and the project files are expected to be untracked until the
   first commit.
3. Run `hcloud server list` before and after any remote test. There should be no
   running servers unless the user intentionally started one.
4. Do not assume `ccx43` works yet. The current Hetzner dedicated-core project
   limit blocks it.
5. Prefer the prebuilt-image path over building Stockfish on every server once
   the GitHub repo and GHCR package exist.

Recommended next implementation sequence:

1. Create/push the GitHub repo, then run `.github/workflows/worker-image.yml` to
   publish `ghcr.io/<owner>/<repo>/stockfish-worker:latest`.
2. Verify `start --skip-build --worker-image ...` on `ccx13` first, then delete
   the server and confirm `hcloud server list` is empty.
3. Add a simple multi-job queue around the existing reusable-server lifecycle.
4. Scaffold the native macOS app under `mac/` using the available macOS skills.

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
- Analysis jobs should reuse a warm server and must not delete it automatically;
  users often want to run several jobs back to back.
- `analyze-fen --stream` emits JSONL `analysis_state` snapshots. The app should
  persist the latest snapshot as state; the final snapshot has
  `status: "completed"` with `bestmove` and `ponder` set.
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
4. Queue one or more positions as remote Stockfish jobs.
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
- Start, stop, retry, and delete jobs.

Expected views:

- Server status: offline, creating, ready, running jobs, deleting, error.
- Live cost panel showing current server runtime, current server estimated cost,
  hourly rate, and accumulated session cost.
- Job list/history with each FEN, parameters, status, result, and timestamps.
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
./bin/stockfish-cloud delete --server stockfish-cloud
```

`analyze-fen` returns one final structured JSON result by default for manual CLI
use and debugging. With `--stream`, it emits JSONL `analysis_state` snapshots
instead. Each running snapshot contains the latest parsed top lines; the final
snapshot uses the same shape with `status: "completed"`, `bestmove`, and
`ponder`.

The faster prebuilt-image start path is:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/<owner>/<repo>/stockfish-worker:latest \
  --skip-build
```

The GitHub Actions workflow becomes active once the repo is pushed to GitHub.

## Worker Image

The fallback smoke-test flow builds the repo's `docker/` worker image on the
temporary server. This proves the lifecycle works, but is too slow and noisy for
production use.

The repo has a prebuilt-image path:

- `.github/workflows/worker-image.yml` publishes to GitHub Container Registry.
- `docs/worker-image.md` documents the image name and usage.
- `start --skip-build --worker-image ghcr.io/<owner>/<repo>/stockfish-worker:latest`
  pulls the image on the Hetzner server instead of compiling Stockfish there.

## State Model

Server lifecycle:

```text
offline -> creating -> booting -> ready -> running -> deleting -> offline
                            \-> error
```

Job lifecycle:

```text
queued -> starting -> running -> completed
                    \-> stopped
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

## Next Steps

1. Push the repo to GitHub and run the worker-image workflow.
2. Extend the CLI from single-FEN analysis to multi-job PGN/FEN queues.
3. Add server/job cost guardrails.
4. Scaffold the native macOS app under `mac/`.
