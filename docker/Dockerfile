FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    make \
    g++ \
    python3 \
  && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/official-stockfish/Stockfish.git /src/Stockfish

WORKDIR /src/Stockfish/src
RUN make -j"$(nproc)" profile-build ARCH=x86-64-avx2

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/Stockfish/src/stockfish /usr/local/bin/stockfish
COPY stockfish-worker /usr/local/bin/stockfish-worker
COPY analyze_fen.py /usr/local/bin/analyze-fen
RUN chmod +x /usr/local/bin/stockfish /usr/local/bin/stockfish-worker /usr/local/bin/analyze-fen

ENTRYPOINT ["/usr/local/bin/stockfish-worker"]
