FROM ubuntu:18.04
ENV DEBIAN_FRONTEND=noninteractive
# 18.04已EOL，公网源搬到old-releases；只留bionic+bionic-updates
# （security/backports在old-releases上没有，留着会整行失败）。
# 另装：xml2（DASH）、vaapi/vdpau/drm（Linux硬解）。
# N卡头文件后续备好再加nvdec（github在部分网络下连不上，先不堵主流程）。
# https的安全库不在这里装（静态编，见下，不欠动态账）。
RUN printf 'deb http://old-releases.ubuntu.com/ubuntu/ bionic main restricted universe multiverse\ndeb http://old-releases.ubuntu.com/ubuntu/ bionic-updates main restricted universe multiverse\n' > /etc/apt/sources.list \
 && rm -f /etc/apt/sources.list.d/*.list \
 && apt-get update && apt-get install -y --no-install-recommends \
      build-essential nasm pkg-config mingw-w64 perl \
      gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
      libxml2-dev libva-dev libvdpau-dev libdrm-dev \
    && rm -rf /var/lib/apt/lists/*
# 安全库静态编一份（x64，openssl-3.0.16.tar.gz由workflow先下到mini/）：
# 单文件so要在哪台机器都能打开，不能动态链老版本安全库。
# 只装静态（no-shared），链接时直接打进so。许可Apache-2，和LGPL拼盘没问题。
COPY mini/openssl-3.0.16.tar.gz /tmp/openssl.tgz
RUN tar -xzf /tmp/openssl.tgz -C /tmp \
 && cd /tmp/openssl-3.0.16 \
 && ./Configure linux-x86_64 -fPIC no-shared --prefix=/opt/ossl-x64 \
 && make -j"$(nproc)" && make install_sw \
 && rm -rf /tmp/openssl-3.0.16 /tmp/openssl.tgz
# zlib静态编一份（x64，zlib-1.3.1.tar.gz由workflow先下到mini/）：
# 给png解码用，不动态链目标机的版本，在哪台机器都打得开。许可zlib，拼盘没问题。
COPY mini/zlib-1.3.1.tar.gz /tmp/zlib.tgz
RUN tar -xzf /tmp/zlib.tgz -C /tmp \
 && cd /tmp/zlib-1.3.1 \
 && ./configure --static --prefix=/opt/zlib-x64 \
 && make -j"$(nproc)" && make install \
 && rm -rf /tmp/zlib-1.3.1 /tmp/zlib.tgz
# zlib静态编一份（mingw64，给win-x64目标用，不欠dll账）。
COPY mini/zlib-1.3.1.tar.gz /tmp/zlib.tgz
RUN tar -xzf /tmp/zlib.tgz -C /tmp \
 && cd /tmp/zlib-1.3.1 \
 && CC=x86_64-w64-mingw32-gcc ./configure --static --prefix=/opt/zlib-w64 \
 && make -j"$(nproc)" && make install \
 && rm -rf /tmp/zlib-1.3.1 /tmp/zlib.tgz
COPY mini/build-one.sh /build-one.sh
RUN chmod +x /build-one.sh
