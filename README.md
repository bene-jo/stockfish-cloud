# stockfish-cloud

Remote Stockfish analysis on short-lived Hetzner Cloud servers.

The idea: start a powerful cloud server when you need analysis, keep it warm
while running several jobs, then delete it so there are no standby compute
costs. The local Mac stays free.

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
  --hash 256 \
  --multipv 3 \
  --movetime 10000
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
`bestmove` and `ponder` set.

Delete the server when done:

```bash
./bin/stockfish-cloud delete --server stockfish-cloud
```

Always check for leftover servers:

```bash
hcloud server list
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

## Product Direction

The planned macOS app should be a native English-language job console for:

- starting/deleting the Hetzner server,
- pasting FENs and configuring analysis parameters,
- running and stopping multiple analysis jobs,
- showing live analysis like Lichess, with current eval and top lines,
- keeping history/results,
- showing live and accumulated estimated costs.

Detailed project memory and implementation context live in `AGENTS.md`.
