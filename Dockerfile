# Multi-stage Dockerfile for imapfilter

# Stage 1: Build imapfilter from source
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    liblua5.4-dev \
    libssl-dev \
    libpcre2-dev \
 && ln -sf /usr/include/lua5.4/*.h /usr/include/ \
 && ln -sf /usr/lib/*-linux-gnu/liblua5.4.so /usr/lib/liblua.so \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY src/imapfilter .

RUN make -j$(nproc) && make install

# Stage 2: Minimal runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    liblua5.4-0 \
    libssl3 \
    libpcre2-8-0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/imapfilter /usr/local/bin/imapfilter
COPY --from=builder /usr/local/share/imapfilter /usr/local/share/imapfilter

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
