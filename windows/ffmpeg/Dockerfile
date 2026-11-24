FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

# The signed Debian snapshot fixes the cross compiler, headers and static zlib.
RUN printf '%s\n' \
      'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20261108T000000Z/ trixie main' \
      > /etc/apt/sources.list && rm /etc/apt/sources.list.d/debian.sources && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gcc libc6-dev gcc-mingw-w64-x86-64-win32 \
      libz-mingw-w64-dev make nasm pkgconf xz-utils && \
    rm -rf /var/lib/apt/lists/*
