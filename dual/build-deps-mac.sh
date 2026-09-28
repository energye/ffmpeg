#!/bin/sh
# mac 外库静态编译（产物 $MACDEPS_PREFIX/<name>-<arch>，默认 /tmp/macdeps）。
# 背景：macos runner 是 ARM64，brew 只有 arm64 瓶；编 x64 full 的烧字件
# （freetype/harfbuzz/fribidi/fontconfig/libass + openh264）必须源码编 x86_64
# 静态 .a，否则 configure 试链拿 arm64 的 dylib 直接挂
# （实测：ignoring file libass.dylib: found architecture 'arm64'）。
# 用法：build-deps-mac.sh [x64|arm64]（工作流只在 x64 full 时调，arm64 走 brew）。
# 版本与 dual/Dockerfile ENV 同源。
set -e
WHICH="${1:-x64}"
SRC=/tmp/macdeps-src
PF="${MACDEPS_PREFIX:-/tmp/macdeps}"
mkdir -p "$SRC" "$PF"
cd "$SRC"

FT=${FREETYPE_VER:-2.13.2}
HB=${HARFBUZZ_VER:-8.3.0}
FB=${FRIBIDI_VER:-1.0.13}
FC=${FONTCONFIG_VER:-2.15.0}
ASS=${LIBASS_VER:-0.17.1}
H264=${OPENH264_VER:-2.4.1}
EXPAT=${EXPAT_VER:-2.6.4}

NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

need() { # file url [fallback-url]
  if [ -f "$1" ]; then return 0; fi
  if curl -fSL --retry 3 --retry-all-errors --max-time 120 -o "$1" "$2" && verify "$1" 2>/dev/null; then
    return 0
  fi
  echo "primary bad for $1, trying fallback" >&2
  rm -f "$1"
  if [ -n "$3" ]; then
    curl -fSL --retry 3 --retry-all-errors --max-time 180 -o "$1" "$3" && verify "$1"
  else
    return 1
  fi
}
verify() { # file : list fully or fail
  case "$1" in
    *.tar.xz) tar tJf "$1" >/dev/null ;;
    *) tar tzf "$1" >/dev/null ;;
  esac
}
need freetype-$FT.tar.gz "https://download.savannah.gnu.org/releases/freetype/freetype-$FT.tar.gz" \
  "https://download-mirror.savannah.gnu.org/releases/freetype/freetype-$FT.tar.gz"
need harfbuzz-$HB.tar.xz "https://github.com/harfbuzz/harfbuzz/releases/download/$HB/harfbuzz-$HB.tar.xz"
need fribidi-$FB.tar.xz "https://github.com/fribidi/fribidi/releases/download/v$FB/fribidi-$FB.tar.xz" \
  "https://download-mirror.savannah.gnu.org/releases/fribidi/fribidi-$FB.tar.xz"
need fontconfig-$FC.tar.gz "https://www.freedesktop.org/software/fontconfig/release/fontconfig-$FC.tar.gz" \
  "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$FC/fontconfig-$FC.tar.gz"
need libass-$ASS.tar.gz "https://github.com/libass/libass/releases/download/$ASS/libass-$ASS.tar.gz"
need openh264-$H264.tar.gz "https://github.com/cisco/openh264/archive/refs/tags/v$H264.tar.gz"
need expat-$EXPAT.tar.gz "https://github.com/libexpat/libexpat/releases/download/R_2_6_4/expat-$EXPAT.tar.gz"
for f in freetype-$FT.tar.gz harfbuzz-$HB.tar.xz fribidi-$FB.tar.xz fontconfig-$FC.tar.gz libass-$ASS.tar.gz openh264-$H264.tar.gz expat-$EXPAT.tar.gz; do
  verify "$f" || { echo "BAD TARBALL $f，删掉重下" >&2; rm -f "$f"; exit 3; }
done

# 编完验片：静态库必须含目标架构，否则后人试链挂得莫名其妙。
check_arch() { # file want-arch
  if ! lipo -info "$1" 2>/dev/null | grep -q "$2"; then
    echo "FAIL: $1 缺 $2 片" >&2; lipo -info "$1" >&2 || true; exit 4
  fi
}

build_one_arch() { # arch-tag
  TAG="$1"
  case "$TAG" in
    x64) ARCHC="-arch x86_64"; HOST="--host=x86_64-apple-darwin"; OARCH=x86_64 ;;
    arm64) ARCHC="-arch arm64"; HOST=""; OARCH=arm64 ;;
    *) echo "unknown $TAG" >&2; exit 2 ;;
  esac
  export CC=clang CXX=clang++ CFLAGS="-O2 $ARCHC" CXXFLAGS="-O2 $ARCHC" LDFLAGS="$ARCHC"

  # expat（静态，fontconfig 的 XML 依赖）。
  rm -rf ex-$TAG && mkdir ex-$TAG && tar -xzf expat-$EXPAT.tar.gz -C ex-$TAG --strip-components=1
  (cd ex-$TAG && ./configure $HOST --disable-shared --enable-static --without-examples --without-tests --without-docbook --prefix=$PF/expat-$TAG && make -j"$NCPU" && make install)
  check_arch $PF/expat-$TAG/lib/libexpat.a $OARCH

  # freetype（静态，harfbuzz 关，免循环依赖）。
  rm -rf ft-$TAG && mkdir ft-$TAG && tar -xzf freetype-$FT.tar.gz -C ft-$TAG --strip-components=1
  (cd ft-$TAG && ./configure $HOST --disable-shared --enable-static --without-harfbuzz --without-bzip2 --without-png --prefix=$PF/freetype-$TAG && make -j"$NCPU" && make install)
  check_arch $PF/freetype-$TAG/lib/libfreetype.a $OARCH

  # meson 交叉描述（Darwin 同系统跨架构，native 配 CFLAGS 不认，必须明说）。
  # 注意：-arch 旗标放 [binaries]/[properties] 会被吞（015/017 实测全变
  # arm64），只放 [built-in options]；pkgconfig 条目改新名 pkg-config。
  cat > /tmp/meson-mac-$TAG.ini <<EOF
[binaries]
c = 'clang'
cpp = 'clang++'
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'
[built-in options]
c_args = ['-arch', '$OARCH']
c_link_args = ['-arch', '$OARCH']
cpp_args = ['-arch', '$OARCH']
cpp_link_args = ['-arch', '$OARCH']
[host_machine]
system = 'darwin'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
  # 交叉前自检：空工程试编，确认 -arch 真进编译行（免得编完才验出 arm64）。
  rm -rf /tmp/meson-probe-$TAG && mkdir -p /tmp/meson-probe-$TAG/src \
    && printf 'int main(void){return 0;}\n' > /tmp/meson-probe-$TAG/src/probe.c \
    && printf "project('probe', 'c')\nexecutable('probe', 'src/probe.c', native: false)\n" > /tmp/meson-probe-$TAG/meson.build \
    && (cd /tmp/meson-probe-$TAG && meson setup --cross-file /tmp/meson-mac-$TAG.ini build >/dev/null && ninja -C build -v 2>&1 | grep -a -m1 'clang.*probe' | grep -a -q -- "-arch $OARCH") \
    || { echo "FAIL: cross 文件 -arch 未生效" >&2; exit 5; }
  echo "cross probe ok: -arch $OARCH 生效"
  # harfbuzz（静态，指向上一步的 freetype；glib 等全关，免得链进 arm64 瓶）。
  # 注意：10.13 部署目标下新 SDK 的 math.h 只声明 __sincosf，不声明 sincosf
  # （harfbuzz VarCompositeGlyph.hh 用了它，_GNU_SOURCE 也救不回来），
  # 直接把调用接到 __sincosf 上（签名一致），否则编到 hb-ot-font 就挂。
  rm -rf hb-$TAG && mkdir hb-$TAG && tar -xJf harfbuzz-$HB.tar.xz -C hb-$TAG --strip-components=1
  (cd hb-$TAG && PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig meson setup --cross-file /tmp/meson-mac-$TAG.ini -Dtests=disabled -Dutilities=disabled -Ddocs=disabled -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled -Dicu=disabled -Dcpp_args="-Dsincosf=__sincosf" -Dc_args="-arch $OARCH" -Dcpp_link_args="-arch $OARCH" -Dc_link_args="-arch $OARCH" --default-library=static --libdir=lib --prefix=$PF/harfbuzz-$TAG build && ninja -C build && ninja -C build install)
  check_arch $PF/harfbuzz-$TAG/lib/libharfbuzz.a $OARCH

  # fribidi（静态）。
  rm -rf fb-$TAG && mkdir fb-$TAG && tar -xJf fribidi-$FB.tar.xz -C fb-$TAG --strip-components=1
  (cd fb-$TAG && meson setup --cross-file /tmp/meson-mac-$TAG.ini -Dtests=false -Ddocs=false -Dbin=false -Dc_args="-arch $OARCH" -Dcpp_args="-arch $OARCH" -Dc_link_args="-arch $OARCH" -Dcpp_link_args="-arch $OARCH" --default-library=static --libdir=lib --prefix=$PF/fribidi-$TAG build && ninja -C build && ninja -C build install)
  check_arch $PF/fribidi-$TAG/lib/libfribidi.a $OARCH

  # fontconfig（静态，指自建三件；libxml2 关，文档关）。
  rm -rf fc-$TAG && mkdir fc-$TAG && tar -xzf fontconfig-$FC.tar.gz -C fc-$TAG --strip-components=1
  (cd fc-$TAG && PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig:$PF/fribidi-$TAG/lib/pkgconfig:$PF/expat-$TAG/lib/pkgconfig ./configure $HOST --disable-shared --enable-static --disable-docs --disable-libxml2 --with-expat=$PF/expat-$TAG --prefix=$PF/fontconfig-$TAG && make -j"$NCPU" && make install)
  check_arch $PF/fontconfig-$TAG/lib/libfontconfig.a $OARCH

  # libass（静态，指自建链）。
  rm -rf as-$TAG && mkdir as-$TAG && tar -xzf libass-$ASS.tar.gz -C as-$TAG --strip-components=1
  (cd as-$TAG && PKG_CONFIG_PATH=$PF/freetype-$TAG/lib/pkgconfig:$PF/harfbuzz-$TAG/lib/pkgconfig:$PF/fribidi-$TAG/lib/pkgconfig:$PF/fontconfig-$TAG/lib/pkgconfig:$PF/expat-$TAG/lib/pkgconfig ./configure $HOST --disable-shared --enable-static --prefix=$PF/ass-$TAG && make -j"$NCPU" && make install)
  check_arch $PF/ass-$TAG/lib/libass.a $OARCH

  # openh264（静态；install 顺带装 dylib，删掉只留 .a，免误链动态）。
  rm -rf h264-$TAG && mkdir h264-$TAG && tar -xzf openh264-$H264.tar.gz -C h264-$TAG --strip-components=1
  (cd h264-$TAG && make CC="clang $ARCHC" CXX="clang++ $ARCHC" ARCH=$(arch_map "$TAG") USE_ASM=No -j"$NCPU" && make CC="clang $ARCHC" CXX="clang++ $ARCHC" ARCH=$(arch_map "$TAG") USE_ASM=No PREFIX=$PF/openh264-$TAG install && rm -f $PF/openh264-$TAG/lib/libopenh264.*.dylib $PF/openh264-$TAG/lib/libopenh264.dylib)
  check_arch $PF/openh264-$TAG/lib/libopenh264.a $OARCH
}

arch_map() {
  case "$1" in
    x64) echo x86_64 ;; arm64) echo aarch64 ;;
  esac
}

case "$WHICH" in
  x64) build_one_arch x64 ;;
  arm64) build_one_arch arm64 ;;
  *) echo "unknown $WHICH" >&2; exit 2 ;;
esac
echo "deps-mac $WHICH done"
