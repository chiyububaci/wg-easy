# As a workaround we have to build on nodejs 18
# nodejs 20 hangs on build with armv6/armv7
FROM docker.io/library/node:18-alpine AS build_node_modules

# Update npm to latest
RUN npm install -g npm@latest

# Copy Web UI
COPY src /app
WORKDIR /app
RUN npm ci --omit=dev &&\
    mv node_modules /node_modules

FROM rust:1.40-slim-buster AS build_boringtun

# Build boringtun
RUN apt update && apt install git -y
RUN git clone https://github.com/cloudflare/boringtun.git /boringtun && cd /boringtun && git reset --hard a0d295653b7b760a12d8b16cc6b353439f5b9649
WORKDIR /boringtun
RUN cargo build --release \
    && strip ./target/release/boringtun

# Copy build result to a new image.
# This saves a lot of disk space.
FROM docker.io/library/node:20-alpine
COPY --from=build_node_modules /app /app

# Move node_modules one directory up, so during development
# we don't have to mount it in a volume.
# This results in much faster reloading!
#
# Also, some node_modules might be native, and
# the architecture & OS of your development machine might differ
# than what runs inside of docker.
COPY --from=build_node_modules /node_modules /node_modules

# Copy boringtun
COPY --from=build_boringtun /boringtun/target/release/boringtun /app

ENV WG_LOG_LEVEL=info \
    WG_THREADS=4

# Install Linux packages
RUN apk add --no-cache \
    dpkg \
    dumb-init \
    iproute2 \
    tcpdump \
    iptables \
    iptables-legacy \
    wireguard-tools

# Use iptables-legacy
RUN update-alternatives --install /sbin/iptables iptables /sbin/iptables-legacy 10 --slave /sbin/iptables-restore iptables-restore /sbin/iptables-legacy-restore --slave /sbin/iptables-save iptables-save /sbin/iptables-legacy-save

# Expose Ports (If needed on buildtime)
#EXPOSE 51820/udp
#EXPOSE 51821/tcp

# Set Environment
ENV DEBUG=Server,WireGuard
ENV WG_QUICK_USERSPACE_IMPLEMENTATION=/app/boringtun

# Run Web UI
WORKDIR /app
CMD ["/usr/bin/dumb-init", "node", "server.js"]
