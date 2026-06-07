# Worker image

The fast production path is to use a prebuilt Stockfish worker image instead of
building Stockfish on every Hetzner server.

## Image name

The GitHub Actions workflow publishes the image to:

```text
ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest
```

The workflow also publishes a commit-specific tag:

```text
ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:<git-sha>
```

## Publishing

Publishing is handled by `.github/workflows/worker-image.yml`.

It runs automatically on pushes to `main` that touch `docker/**`, and it can be
started manually from the GitHub Actions tab with `workflow_dispatch`.

The workflow uses GitHub's built-in `GITHUB_TOKEN` with `packages: write`, so no
personal access token should be committed or configured in this repo.

The default image is built with:

```text
STOCKFISH_REF=sf_18
STOCKFISH_ARCH=x86-64-avx2
```

`x86-64-avx2` keeps `latest` compatible with the current `ccx33` default. Faster
CPU-specific images can be built by overriding `STOCKFISH_ARCH`, but they should
use separate tags and only run on server types that expose the required
instructions.

## Using a prebuilt image

Start a server with the published image:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --skip-build
```

With `--skip-build`, the CLI installs Docker on the Hetzner server and pulls the
image instead of uploading `docker/` and compiling Stockfish there.

Run jobs against the warm server:

```bash
./bin/stockfish-cloud analyze-fen \
  --server stockfish-cloud \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
  --multipv 3 \
  --movetime 10000
```

Delete the server when done:

```bash
./bin/stockfish-cloud delete --server stockfish-cloud
```

## Why this matters

The first remote smoke tests showed that Stockfish analysis itself is fast, but
building Stockfish from source on a fresh server takes several minutes. A
prebuilt image moves that cost to CI and makes each server start much closer to
"create, pull, run".
