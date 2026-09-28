FROM ubuntu:18.04
ENV DEBIAN_FRONTEND=noninteractive
# gpui 双版本单文件构建镜像（本机 docker 和 GitHub Actions 共用）。
# 基座 ubuntu18.04（glibc 2.27，产物最低跑 Ubuntu 18.04 / CentOS 8 /
# Debian 10 一代）；18.04 已 EOL，apt 源走 old-releases。
# 基础版零外库；高级版烧字件 + openh264 全静态编进单文件（-fPIC no-shared），
# 用户机器不用装，许可保持 LGPL 2.1（x264/x265/fdk 一个不装）。
RUN printf 'deb http://archive.ubuntu.com/ubuntu/ bionic main restricted universe multiverse\ndeb http://archive.ubuntu.com/ubuntu/ bionic-updates main restricted universe multiverse\ndeb http://security.ubuntu.com/ubuntu/ bionic-security main restricted universe multiverse\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      build-essential nasm pkg-config perl git curl ca-certificates \
      mingw-w64 ninja-build \
      gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross \
      gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross \
      gcc-i686-linux-gnu g++-i686-linux-gnu libc6-dev-i386-cross \
      libxml2-dev libva-dev libvdpau-dev libdrm-dev libexpat1-dev \
      zlib1g-dev liblzma-dev \
      libssl-dev libffi-dev libbz2-dev libsqlite3-dev libreadline-dev \
      python3-dev \
    && rm -rf /var/lib/apt/lists/* \
 && ninja --version

# 版本钉死（和 build-deps.sh 默认值 + third_party 包三处同步，升级改三处）。
ENV OPENSSL_VER=3.5.8 \
    ZLIB_VER=1.3.2 \
    EXPAT_VER=2.8.5 \
    FREETYPE_VER=2.14.3 \
    HARFBUZZ_VER=14.5.0 \
    FRIBIDI_VER=1.0.17 \
    FONTCONFIG_VER=2.18.3 \
    LIBASS_VER=0.17.5 \
    OPENH264_VER=2.6.0 \
    PYTHON_VER=3.11.16 \
    LLVM_MINGW_VER=20230320

# Python 3.11（源码编到 /usr/local）：bionic 自带 python3.6 跑不动
# meson 新版，而 fontconfig 2.18 只要 meson>=1.11 且只有 meson 构建。
# 编完 pip 装新版 meson（harfbuzz/fribidi/fontconfig 都走它）。
# 注意：configure 时 TMPDIR 必须指到大分区——make install 末尾 ensurepip
# 解包 pip 轮子到 $TMPDIR，容器默认 /tmp 没问题，但有些环境 TMPDIR 指向
# 小分区会报 No such file；显式导出 TMPDIR=/var/tmp 保底。
COPY third_party/Python-3.11.16.tar.xz /tmp/Python.tar.xz
RUN tar -xJf /tmp/Python.tar.xz -C /tmp \
 && cd /tmp/Python-3.11.16 \
 && ./configure --prefix=/usr/local --enable-optimizations=no --without-ensurepip \
 && make -j"$(nproc)" && make install \
 && rm -rf /tmp/Python-3.11.16 /tmp/Python.tar.xz \
 && cd /tmp \
 && curl -sS --retry 3 -o /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py \
 && /usr/local/bin/python3 /tmp/get-pip.py \
 && rm -f /tmp/get-pip.py \
 && /usr/local/bin/pip3 install --no-cache-dir "meson>=1.11" \
 && ln -sf /usr/local/bin/meson /usr/bin/meson \
 && meson --version
# 冒烟工具（meson 0.61 + ninja，跑系统 python3.6）：只给本机冒烟用，
# 让"旧 meson 能否带动新依赖"可验证；CI 正式构建走上面 Python 3.11 的新 meson。
# 包都在本仓（全离线）：16 个 bionic .deb（pip 全家桶）+ meson 0.61.5 轮子。
# 注意：meson 必须装进 python3.6 的 dist-packages（默认 pip install，不加
# --target），否则 ninja 里 meson 回调（/usr/bin/python3 -m mesonbuild…）
# 找不到模块直接炸（实测 fribidi 挂在这）。
COPY third_party/apt/*.deb /tmp/apt/
COPY third_party/pypi/*.whl /tmp/pypi/
RUN dpkg -i /tmp/apt/*.deb \
 && pip3 install --no-index --find-links /tmp/pypi meson \
 && rm -rf /tmp/apt /tmp/pypi \
 && meson --version

# llvm-mingw（win-arm64 真 ARM64 用；x64 mingw 打不出 arm64）。
# 20230320 是最后一个带 ubuntu-18.04 包的版本（glibc 2.27 能跑；
# 新版只要 22.04 包，glibc 2.35，在 18.04 容器里跑不起来）。
# 注意：必须装到 /usr/local 下，不能放 /opt——构建时 /tmp/depopt
# 挂载到 /opt 会把镜像里的 /opt 盖掉（实测 clang 失踪）。
COPY third_party/llvm-mingw-20230320.tar.xz /tmp/llvm-mingw.tar.xz
RUN mkdir -p /usr/local/llvm-mingw && \
    tar -xJf /tmp/llvm-mingw.tar.xz -C /usr/local/llvm-mingw --strip-components=1 && \
    rm -f /tmp/llvm-mingw.tar.xz
ENV PATH="/usr/local/llvm-mingw/bin:${PATH}"

# 386 用独立交叉包 i686-linux-gnu（不用宿主 gcc -m32：multilib 与
# arm 交叉包在 bionic 上互斥，装不上；独立交叉包无此问题）。
# 构建上下文是 ffmpeg 仓根目录（docker build -f dual/Dockerfile .）。
COPY dual/build-deps.sh /build-deps.sh
RUN chmod +x /build-deps.sh
COPY dual/build-one.sh /build-one.sh
RUN chmod +x /build-one.sh
COPY dual/build-one-mac.sh /build-one-mac.sh
RUN chmod +x /build-one-mac.sh
