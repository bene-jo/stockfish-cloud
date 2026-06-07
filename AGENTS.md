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

1. Continue the native macOS app under `mac/`.
2. Add local persistence for positions/history.
3. Harden server/action error handling in the UI.

Open product requirement to preserve: the macOS app must show live analysis,
similar in spirit to Lichess, with current eval, current depth/nps, and the top
N lines updating while a job runs.

## Current State

- Hetzner CLI context: `stockfish-cloud`.
- Hetzner SSH key name: `macbook-stockfish-cloud`.
- Confirmed working server types in `fsn1`: `ccx13`, `ccx33`, `cpx52`,
  `cpx62`.
- Current Hetzner account limit allows `ccx33` but blocks `ccx43` with
  `dedicated core limit exceeded`.
- Default reusable server name: `stockfish-cloud`.
- GitHub repo: `https://github.com/bene-jo/stockfish-cloud`.
- Published worker image:
  `ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`.
- Published Genoa-optimized worker image:
  `ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:genoa`.
- First worker-image workflow run succeeded on 2026-06-07:
  `https://github.com/bene-jo/stockfish-cloud/actions/runs/27076443609`.
- GitHub Actions were updated to current Node.js 24-compatible major versions
  on 2026-06-07 after GitHub warned that older Node.js 20 actions are being
  phased out. The updated worker-image run succeeded:
  `https://github.com/bene-jo/stockfish-cloud/actions/runs/27076587960`.
- GHCR image pull was verified on a fresh `ccx13` server with
  `start --skip-build --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`.
- Analysis jobs should reuse a warm server and must not delete it automatically;
  users often want to run several positions back to back.
- For accuracy on `ccx33`, run only one Stockfish analysis at a time. The app
  disables new analyses while one is running, and the CLI refuses to start a new
  labeled analysis container if another one is already running.
- `analyze-fen --stream` emits JSONL `analysis_state` snapshots. The app should
  persist the latest snapshot as state; the final snapshot has
  `status: "completed"` with `bestmove` and `ponder` set.
- Analysis scores exposed to the app are normalized so positive means White is
  better. Keep `rawScore` only as a debugging/comparison field.
- Principal variations should include SAN notation for app display. Raw UCI PV
  moves can stay in JSON for debugging and future tooling.
- The worker image should use the current official stable Stockfish release
  (`sf_18` as of 2026-06-07), not an older engine and not a random development
  pre-release. Update this deliberately when a newer stable release exists.
- `analyze-position` is the app-facing analysis command. It defaults to
  streamed JSONL, depth `60`, `3` lines, and `14336 MB` hash.
- The macOS app does not expose depth selection in the first stability-driven
  flow. The remote worker analyzes until the live stability indicator reaches
  `stable`, then stops Stockfish automatically. Depth `60` is the hidden safety
  boundary if stability is not reached.
- When `analyze-fen` / `analyze-position` use a non-local worker image, the CLI
  pulls that image before running analysis. This prevents already-running warm
  servers from using stale `latest` layers after GHCR publishes a new worker.
  Treat this as a development-safe default, not the final production strategy.
  Production should pull on server start, record the exact worker image
  tag/digest in server/app state, and pull again only when the desired worker
  version changed or the image is missing.
- `stop-position --position-id ...` stops the named remote Docker container for
  a running analysis. Stop is an action, not a separate position state; terminal
  stream snapshots still use `status: "completed"`.
- `status --json` returns app-facing server status, uptime, hourly rate, and
  estimated live cost.
- Native macOS app scaffold lives under `mac/` as a SwiftPM SwiftUI executable
  product named `StockfishCloud`.
- Project-level run entrypoint: `./script/build_and_run.sh`. It builds the
  SwiftPM app, stages `dist/StockfishCloud.app`, launches it as a real app
  bundle, and is wired to `.codex/environments/environment.toml`.
- The app uses the local `bin/stockfish-cloud` CLI rather than a public API.
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
simple as pasting positions into a native list, while keeping local Mac
resources free.

All user-facing UI text should be in English.

Primary user flow:

1. Start a Hetzner server and keep it warm while useful.
2. Paste one or more FENs.
3. Choose analysis parameters.
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

The current macOS app build/run shape is:

```bash
./script/build_and_run.sh
```

Use `./script/build_and_run.sh --verify` to build, launch, and confirm the
`StockfishCloud` process exists.

`analyze-fen` returns one final structured JSON result by default for manual CLI
use and debugging. With `--stream`, it emits JSONL `analysis_state` snapshots
instead. Each running snapshot contains the latest parsed top lines; the final
snapshot uses the same shape with `status: "completed"`, `bestmove`, and
`ponder`.

`analyze-position` is the app-facing wrapper around `analyze-fen`. It defaults
to `--stream`, `--depth 60`, `--lines 3`, and a generated `positionId` if the
caller does not provide one. When a `positionId` is present, the remote Docker
container is named `stockfish-position-<positionId>` so `stop-position` can stop
it from another app action.

The stability indicator is derived by the remote worker and streamed as
`stability` in each `analysis_state`. The macOS app must display the streamed
state/reason and must not independently re-derive stability.

Stability states are only:

- `unstable`
- `settling`
- `stable`

Each stability report includes a human-readable `reason`. If the hidden depth
boundary is reached before `stable`, keep showing the last streamed state
(`unstable` or `settling`) and reason; do not introduce a separate max-depth
state.

Completed depth sample definition: a depth is sampleable only after all
requested MultiPV lines have reported that exact depth and the engine has moved
on to a deeper depth, because Stockfish can still revise rows while it is
working on the same depth. At analysis completion, the worker finalizes any
remaining complete depths. The worker samples finalized exact-depth MultiPV
snapshots, not mixed latest-line state.

Only exact UCI score updates are eligible as stability evidence. Updates marked
`lowerbound` or `upperbound` may still be streamed for live display, but they are
provisional search bounds and must not be used to decide `settling` or `stable`.

Current stability parameters:

- Hidden boundary: depth `60`.
- Default app/CLI hash: `14336 MB`.
- Hash restarts are a recovery path, not a normal operating mode. Keep the
  default hash high enough on `ccx33` that restarts should be rare in ordinary
  analyses.
- If `hashfull >= 900` and memory allows a larger hash, the worker stops the
  current pass, doubles the hash up to its memory-aware cap, clears hash, and
  restarts the same position. This is preferable to running to depth `60` with a
  saturated hash and a permanent warning.
- The same hash-growth rule applies when the hash saturation is discovered only
  while finalizing the last completed depth after `bestmove`.
- `settling`: depth `32+`, at least `150,000,000` nodes, at least `6`
  finalized complete depth samples spanning `5+` depths, every displayed line
  has at least `8` UCI plies, score drift by displayed rank is at most `0.10`
  pawns for line 1 and `0.15` for lines 2-3, and neighboring-line gap drift is
  at most `0.20` pawns.
- `stable`: depth `40+`, at least `300,000,000` nodes, at least `10`
  finalized complete depth samples spanning `9+` depths, every displayed line
  has at least `8` UCI plies, score drift by displayed rank is at most `0.06`
  pawns for line 1 and `0.10` for lines 2-3, and neighboring-line gap drift is
  at most `0.12` pawns.
- PV identity/order is not a stability blocker. If two candidate moves keep
  swapping order because their evals are consistently close, that should count
  as stable eval evidence rather than instability.
- If hash is already at the memory-aware cap and `hashfull >= 900`, stability
  remains `unstable` with a reason explaining the hash limit.
- Worker reasons should describe the next reachable gate. For example, between
  depths `30` and `40`, the reason should explain why `settling` is not reached,
  not merely say that `stable` requires depth `40+`.
- Stability states are evidence-derived, not monotonic by fiat. `settling`
  should be hard enough to earn that ordinary runs do not flicker casually, but
  a real PV/eval break can still return the state to `unstable`.
- Open follow-up from real probes: expose analysis pass/restart history in the
  streamed state. If the worker restarts with a larger hash and the user stops
  during the second pass, the latest `completeDepth` can be lower than the
  previous pass's reached depth, which is technically correct but confusing
  without context.

The minimum depth gates are confidence/evidence gates, not a theoretical claim
that lower-depth positions cannot be stable. They prevent the UI from presenting
early convergence as a trustworthy stop condition.

The faster prebuilt-image start path is:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --skip-build
```

The GitHub Actions workflow is active on `main`.

Worker/app analysis display conventions:

- Use current stable Stockfish (`sf_18` on 2026-06-07) or newer stable releases.
- Prefer analysis settings that are at least as accurate as the visible Lichess
  configuration. Keep `ccx33` app analyses at `8` threads and `14336 MB` hash
  rather than copying a smaller Lichess browser hash display.
- Display evaluations from White's perspective, with positive values meaning
  White is better.
- Display principal variations in SAN with move numbers, while preserving raw
  UCI moves in JSON for debugging.

## Performance Findings

Performance investigation on 2026-06-07:

- `ccx33` in `fsn1` presented as AMD EPYC Milan with `8` vCPUs, but topology
  showed `4` physical cores with `2` hardware threads each. It supports AVX2 and
  BMI2, but not AVX-512/VNNI.
- On `ccx33`, Stockfish `sf_18` build targets `x86-64-avx2`, `x86-64-bmi2`,
  and `native` were effectively tied. `native` selected `x86-64-bmi2`.
- On the same representative FEN with MultiPV 3, `Threads=8`,
  `Hash=14336 MB`, and a 15 second search, `ccx33` produced about
  `5.1M-5.3M nps`. This matches the macOS app's observed `~5M nps`, so the app
  is not leaving an obvious local implementation win on the table.
- `Threads=4` on `ccx33` produced about `3.7M-3.9M nps` on the same workload.
  Keep `Threads=8` for raw speed on `ccx33`.
- `Hash=4096 MB` versus `14336 MB` did not materially change short-run nps on
  the representative workload. The larger hash is still useful for long stable
  searches because it delays or avoids hash saturation.
- ARM `cax31`/`cax41` capacity was unavailable in `fsn1`, `nbg1`, and `hel1`
  during the probe, so no ARM performance conclusion was reached.
- `cpx52` in `fsn1` presented as shared AMD EPYC Genoa with `12` visible cores,
  one thread per core, and AVX-512/VNNI flags exposed. It is cheaper than
  `ccx33` in EU price data at probe time (`0.069615 EUR/h` gross vs
  `0.119119 EUR/h` gross), but it is shared CPU rather than dedicated CPU.
- On `cpx52` with the current AVX2 worker image, the representative MultiPV 3
  workload produced about `10.6M-10.7M nps` at `Threads=12`.
- On `cpx52`, locally built Stockfish `x86-64-avx512icl`,
  `x86-64-vnni512`, and `native` builds improved real workload throughput over
  AVX2. Best observed representative run was `native`, `Threads=12`,
  `Hash=14336 MB`: about `12.2M nps`.
- Practical performance direction: validate `cpx52` plus the separate
  Genoa/AVX-512 worker image tag as a faster option. Do not replace the
  compatible `latest` image with an AVX-512/VNNI binary unless server selection
  guarantees the CPU supports it.
- The Genoa image uses `STOCKFISH_ARCH=x86-64-vnni512`. The best explicit
  target in the short representative probe was `x86-64-vnni512`; `native`
  varied slightly higher in one run but is not suitable for CI because it would
  target the GitHub runner CPU instead of the Hetzner Genoa host.
- The published `stockfish-worker:genoa` image was validated on `cpx52` and
  `cpx62` on 2026-06-07.
- `cpx52` with `stockfish-worker:genoa`, `Threads=12`, and the representative
  MultiPV 3 workload:
  - Bench: about `14.4M nps`.
  - 60 second analysis: about `11.2M nps`, depth `33`, `673M` nodes, hash capped
    to `11728 MB`, final `hashfull=303`.
  - 5 minute analysis: about `10.9M nps`, depth `41`, `3.28B` nodes, final
    `hashfull=920`. This is too close to saturation for trusted long stability.
- `cpx62` in `fsn1` presented as shared AMD EPYC Genoa with `16` visible cores,
  one thread per core, AVX-512/VNNI flags exposed, and `32 GB` RAM. EU gross
  hourly price at probe time was `0.096271 EUR/h`, still below `ccx33`.
- `cpx62` with `stockfish-worker:genoa`, `Threads=16`, and the representative
  MultiPV 3 workload:
  - Bench: about `17.9M nps`.
  - 60 second analysis: about `14.1M nps`, depth `32`, `848M` nodes,
    `14336 MB` hash, final `hashfull=307`.
  - 5 minute analysis with requested `24576 MB` hash was memory-capped to
    `15665 MB`: about `14.2M nps`, depth `41`, `4.25B` nodes, final
    `hashfull=909`.
- Current interpretation: `cpx62` plus the Genoa image is the strongest
  performance candidate measured so far, and probably the better experimental
  app server type than `cpx52`. Do not make it the unquestioned default yet:
  shared CPU variance and long-run hash saturation still need product decisions
  or worker changes.

## Worker Image

The fallback smoke-test flow builds the repo's `docker/` worker image on the
temporary server. This proves the lifecycle works, but is too slow and noisy for
production use.

The repo has a prebuilt-image path:

- `.github/workflows/worker-image.yml` publishes to GitHub Container Registry.
- `docs/worker-image.md` documents the image name and usage.
- `start --skip-build --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest`
  pulls the image on the Hetzner server instead of compiling Stockfish there.
- `docker/Dockerfile` accepts `STOCKFISH_ARCH` and
  `STOCKFISH_BUILD_TARGET`. The workflow keeps `stockfish-worker:latest` on
  `x86-64-avx2` with `profile-build` for `ccx33` compatibility, and publishes
  `stockfish-worker:genoa` with `x86-64-vnni512` and plain `build`.

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
- `cpx52`: about `0.069615 EUR/h`.
- `cpx62`: about `0.096271 EUR/h`.

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
- Left pane: compact server panel, `New Position` form only while the server is
  running, then `Positions`.
- Server panel only needs status, uptime, live cost, and either start or delete.
- Position creation takes FEN, number of lines, and `Start Analysis`.
- Positions list should show running and completed positions together without
  completed badges or queue language.
- Right pane: selected position details only; no board in the first version.
- Focus details on depth, stability, time running, nodes/sec, and top lines with
  evals.
- Show a small engine metadata pane below the top lines with version, NNUE,
  threads, hash, lines, and target.
- Do not model user-stopped positions as a separate UI state in the first
  version; use the stability label and terminal depth to show whether the app
  stopped because analysis stabilized or hit the hidden boundary.
- Do not include redundant parameters, raw engine output, standalone eval, or
  best-move blocks in the initial UI.

## Next Steps

1. Add local persistence for positions/history.
2. Harden server/action error handling in the UI.
3. Exercise a full app-driven remote analysis session on `ccx13`.
