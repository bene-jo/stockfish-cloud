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

ARG STOCKFISH_REF=sf_18
ARG STOCKFISH_ARCH=x86-64-avx2
ARG STOCKFISH_BUILD_TARGET=profile-build
RUN git clone --depth 1 --branch "${STOCKFISH_REF}" https://github.com/official-stockfish/Stockfish.git /src/Stockfish

WORKDIR /src/Stockfish/src
RUN make -j"$(nproc)" "${STOCKFISH_BUILD_TARGET}" ARCH="${STOCKFISH_ARCH}"

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3-pip \
    python3 \
  && python3 -m pip install --break-system-packages --no-cache-dir chess==1.11.2 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/Stockfish/src/stockfish /usr/local/bin/stockfish
COPY stockfish-worker /usr/local/bin/stockfish-worker
COPY analyze_fen.py /usr/local/bin/analyze-fen
RUN chmod +x /usr/local/bin/stockfish /usr/local/bin/stockfish-worker /usr/local/bin/analyze-fen

ENTRYPOINT ["/usr/local/bin/stockfish-worker"]
