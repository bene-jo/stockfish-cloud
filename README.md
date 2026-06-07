# stockfish-cloud

Remote Stockfish analysis on short-lived Hetzner Cloud servers.

The idea: start a powerful cloud server when you need analysis, keep it warm
while running several positions one after another, then delete it so there are
no standby compute costs. The local Mac stays free.

## Current Status

- Hetzner CLI automation works.
- Remote Stockfish benchmark and FEN analysis have been smoke-tested.
- `ccx13` and `ccx33` work in `fsn1`.
- `ccx43` is currently blocked by the Hetzner dedicated-core project limit.
- A GitHub Actions workflow is ready to publish a prebuilt worker image to GHCR.

## Quick Start

Check local Hetzner setup:

```bash
hcloud context list
hcloud ssh-key list
```

Start and prepare a reusable server:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --location fsn1 \
  --ssh-key macbook-stockfish-cloud
```

Analyze a position:

```bash
./bin/stockfish-cloud analyze-fen \
  --server stockfish-cloud \
  --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
  --threads 8 \
  --hash 4096 \
  --multipv 3 \
  --movetime 10000
```

Analyze a UI-style position with live JSONL state:

```bash
./bin/stockfish-cloud analyze-position \
  --server stockfish-cloud \
  --position-id position-1 \
  --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
  --lines 3
```

Stop a running position:

```bash
./bin/stockfish-cloud stop-position \
  --server stockfish-cloud \
  --position-id position-1
```

Stream live analysis state updates as JSONL:

```bash
./bin/stockfish-cloud analyze-fen \
  --server stockfish-cloud \
  --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
  --multipv 3 \
  --movetime 10000 \
  --stream
```

In stream mode, each JSONL line is an `analysis_state` snapshot. The app can
persist the latest snapshot; the final snapshot has `status: "completed"` with
`bestmove` and `ponder` set. Engine scores are normalized so positive means
White is better. Principal variations include both raw UCI moves and SAN
notation for the app UI.

When using a GHCR worker image, analysis commands pull the image before running
so an already-warm server does not keep using stale `latest` layers.

For accuracy, run one analysis at a time on `ccx33`. The default analysis hash
is `4096 MB`. The remote worker analyzes until the top lines are stable, then
stops automatically, with depth `60` as the hidden safety boundary. Stability is
streamed as `unstable`, `settling`, or `stable` with a human-readable reason.

Delete the server when done:

```bash
./bin/stockfish-cloud delete --server stockfish-cloud
```

Always check for leftover servers:

```bash
hcloud server list
```

Get app-facing server state and estimated live cost:

```bash
./bin/stockfish-cloud status --json
```

## Fast Worker Image Path

The worker image is published to GHCR:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --skip-build
```

See `docs/worker-image.md` for details.

## macOS App

Build and launch the SwiftUI app:

```bash
./script/build_and_run.sh
```

The first app version lives under `mac/`. It uses the local CLI to read server
status, start/delete the server, stream position analysis, and stop a running
position.

## Product Direction

The planned macOS app should be a native English-language job console for:

- starting/deleting the Hetzner server,
- pasting FENs and configuring analysis parameters,
- running and stopping position analyses one at a time,
- showing live analysis like Lichess, with current eval and top lines,
- keeping history/results,
- showing live and accumulated estimated costs.

Detailed project memory and implementation context live in `AGENTS.md`.
