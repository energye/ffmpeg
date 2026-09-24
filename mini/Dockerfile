FROM ubuntu:18.04
ENV DEBIAN_FRONTEND=noninteractive
# 18.04软件源已搬到old-releases，先换源再装工具链。
RUN sed -i 's/archive.ubuntu.com/old-releases.ubuntu.com/g; s/security.ubuntu.com/old-releases.ubuntu.com/g' /etc/apt/sources.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      build-essential nasm pkg-config mingw-w64 \
      gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
    && rm -rf /var/lib/apt/lists/*
COPY mini/build-one.sh /build-one.sh
RUN chmod +x /build-one.sh
