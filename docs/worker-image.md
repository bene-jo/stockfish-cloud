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

It also publishes an optimized Genoa/AVX-512 image:

```text
ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:genoa
ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:genoa-<git-sha>
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
STOCKFISH_BUILD_TARGET=profile-build
```

`x86-64-avx2` keeps `latest` compatible with older `ccx33` runs. Faster
CPU-specific images can be built by overriding `STOCKFISH_ARCH`, but they should
use separate tags and only run on server types that expose the required
instructions.

The `genoa` image is built with:

```text
STOCKFISH_REF=sf_18
STOCKFISH_ARCH=x86-64-vnni512
STOCKFISH_BUILD_TARGET=build
```

It requires a CPU with AVX-512/VNNI support, such as the tested Hetzner
`cpx52`/`cpx62` Genoa hosts. It deliberately uses `build` instead of
`profile-build` because Stockfish profile builds execute the compiled binary
during the Docker build, and GitHub-hosted runners may not expose the required
AVX-512/VNNI instructions.

## Using a prebuilt image

Start a server with the published image:

```bash
./bin/stockfish-cloud start \
  --server-type ccx33 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:latest \
  --skip-build
```

Start a Genoa-capable server with the optimized image:

```bash
./bin/stockfish-cloud start \
  --server-type cpx62 \
  --worker-image ghcr.io/bene-jo/stockfish-cloud/stockfish-worker:genoa \
  --skip-build
```

The `genoa` image is only safe on compatible CPUs. Do not use it on `ccx33`.
The app default is currently `cpx62`, but `cpx52`/`cpx62` are shared CPU
instances, so keep watching sustained throughput variance in real use.

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
