FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
# gpui 双版本单文件构建镜像（本机 docker 和 GitHub Actions 共用）。
# 基础版零外库；高级版烧字四件 + openh264 全静态编进单文件（-fPIC no-shared），
# 用户机器不用装，许可保持 LGPL 2.1（x264/x265/fdk 一个不装）。
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential nasm pkg-config perl git curl gperf ca-certificates \
      mingw-w64 \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
      gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross \
      gcc-11-multilib g++-11-multilib libc6-dev-i386 \
      libxml2-dev libva-dev libvdpau-dev libdrm-dev libexpat1-dev \
      zlib1g-dev liblzma-dev \
      meson ninja-build \
    && rm -rf /var/lib/apt/lists/*

# 版本钉死（和 build-deps.sh 默认值同步，升级改两处 + 真源一行）。
ENV OPENSSL_VER=3.0.16 \
    ZLIB_VER=1.3.1 \
    EXPAT_VER=2.6.4 \
    FREETYPE_VER=2.13.2 \
    HARFBUZZ_VER=8.3.0 \
    FRIBIDI_VER=1.0.13 \
    FONTCONFIG_VER=2.15.0 \
    LIBASS_VER=0.17.1 \
    OPENH264_VER=2.4.1 \
    LLVM_MINGW_VER=20231003

# llvm-mingw（win-arm64 真 ARM64 用；x64 mingw 打不出 arm64，之前
# win-arm64 复用 x86_64 前缀是错的，已拆开。70M，一次下载）。
# 注意：必须装到 /usr/local 下，不能放 /opt——构建时 /tmp/depopt
# 挂载到 /opt 会把镜像里的 /opt 盖掉（实测 clang 失踪）。
RUN curl -sSL --retry 3 --retry-all-errors -o /tmp/llvm-mingw.tar.xz \
      https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VER/llvm-mingw-$LLVM_MINGW_VER-msvcrt-ubuntu-20.04-x86_64.tar.xz && \
    mkdir -p /usr/local/llvm-mingw && \
    tar -xJf /tmp/llvm-mingw.tar.xz -C /usr/local/llvm-mingw --strip-components=1 && \
    rm -f /tmp/llvm-mingw.tar.xz
ENV PATH="/usr/local/llvm-mingw/bin:${PATH}"

# 386 用宿主 gcc -m32（非独立交叉包），内核头是 x86_64 那套；
# openssl 的 apps 在 -m32 下找 i386-linux-gnu/asm 找不到（只有
# x86_64-linux-gnu/asm），链个同构软链接顶上（头文件内容同构，实测可用）。
RUN mkdir -p /usr/include/i386-linux-gnu && \
    ln -sfn ../x86_64-linux-gnu/asm /usr/include/i386-linux-gnu/asm
# 构建上下文是 ffmpeg 仓根目录（docker build -f dual/Dockerfile .）。
COPY dual/build-deps.sh /build-deps.sh
RUN chmod +x /build-deps.sh
COPY dual/build-one.sh /build-one.sh
RUN chmod +x /build-one.sh
COPY dual/build-one-mac.sh /build-one-mac.sh
RUN chmod +x /build-one-mac.sh
