#!/bin/sh
# mac 单文件：编一个 arch 的一个版本（在 macos-14 runner 上直接跑，不用 docker）。
# 用法：build-one-mac.sh <arm64|x64> <base|full>
# 产物：$OUTDIR/darwin-<arch>/libgpui_ffmpeg.dylib（基础版）或
#       $OUTDIR/darwin-<arch>/libgpui_ffmpeg_full.dylib（高级版）
# 源码默认用检出目录本身（SRC=脚本所在仓根），可用 SRC 环境变量另指。
# 配方唯一真源：本仓 dual/recipe（Go 命令），这里只管拼 mac 平台部分。
# 许可：两档都不碰 GPL（x264/x265/fdk 一个不开），LGPL 2.1 不变。
# 依赖：brew install nasm pkg-config freetype harfbuzz fontconfig fribidi libass openh264
# （workflow 已装；full 缺料时走 build-one.sh 同款容错：丢开关+连带滤镜，不卡死）。
set -e
ARCH="$1"
V="${2:-base}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BLD="/tmp/b-darwin-$ARCH-$V"
SRC="${SRC:-$REPO}"
OUTDIR="${OUTDIR:-$REPO/out}"
OUT="$OUTDIR/darwin-$ARCH"
mkdir -p "$BLD" "$OUT"
cd "$BLD"

if [ -f /tmp/recipe.flags ]; then
  COMMON=$(cat /tmp/recipe.flags)
elif [ -n "$RECIPE_FLAGS" ]; then
  COMMON="$RECIPE_FLAGS"
else
  COMMON=$(cd "$REPO/dual" && go run ./recipe -variant "$V")
fi

# mac 编 x64 是交叉（-arch x86_64 皮），configure 的 pkg-config 检测
# 跑的是 x86_64 二进制，brew 的 arm64 .pc 缺 x86_64 段就报找不到。
# 先把 PKG_CONFIG_PATH 指到 brew 前缀；同时打印 config.log 里
# libass 那段，下轮定位。
if [ -d /opt/homebrew/lib/pkgconfig ]; then
  export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
if [ -d /usr/local/lib/pkgconfig ]; then
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
if [ -d /opt/homebrew/opt/openh264/lib/pkgconfig ]; then
  export PKG_CONFIG_PATH="/opt/homebrew/opt/openh264/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
fi
trap 'echo "=== config.log libass ==="; grep -a -A15 "check_pkg_config libass" ffbuild/config.log 2>/dev/null | head -40 || true' EXIT
# full 缺料容错（同 build-one.sh）：pkg-config 找不到就丢开关+连带滤镜。
FULL_DEPS_MAC=""
FULL_DROP=""
if [ "$V" = "full" ]; then
  want_pc="libfreetype:freetype2 libharfbuzz:harfbuzz libfontconfig:fontconfig libfribidi:fribidi libass:libass libopenh264:openh264"
  for pair in $want_pc; do
    lib="${pair%%:*}"; pc="${pair##*:}"
    if pkg-config --exists "$pc" 2>/dev/null; then
      FULL_DEPS_MAC="$FULL_DEPS_MAC --enable-$lib"
    else
      echo "WARN: 缺外库 $pc，丢掉 --enable-$lib（本次 mac full 无此功能）" >&2
      FULL_DROP="$FULL_DROP --enable-$lib"
    fi
  done
  case "$FULL_DROP" in
    *--enable-libass*) FULL_DROP="$FULL_DROP --enable-filter=subtitles --enable-filter=ass" ;;
  esac
  case "$FULL_DROP" in
    *--enable-libfreetype*|*--enable-libharfbuzz*) FULL_DROP="$FULL_DROP --enable-filter=drawtext" ;;
  esac
  if [ -n "$FULL_DROP" ]; then
    NEW_COMMON=""
    for tok in $COMMON; do
      skip=0
      for d in $FULL_DROP; do
        if [ "$tok" = "$d" ]; then skip=1; break; fi
      done
      if [ "$skip" = "0" ]; then NEW_COMMON="$NEW_COMMON $tok"; fi
    done
    COMMON="$NEW_COMMON"
    echo "WARN: 本次 mac full 丢掉:$FULL_DROP" >&2
  fi
fi

LIB=libgpui_ffmpeg.dylib
if [ "$V" = "full" ]; then
  LIB=libgpui_ffmpeg_full.dylib
fi
# mac 用系统 VideoToolbox 硬解，不添第三方依赖；openssl 走系统 SecureTransport 思路，
# 这里保持与 linux 一致开 openssl（brew openssl，有就链，没有 configure 会报错再调）。
MAC_BASE="--enable-videotoolbox --enable-hwaccel=h264_videotoolbox --enable-hwaccel=hevc_videotoolbox --enable-hwaccel=vp9_videotoolbox --enable-hwaccel=av1_videotoolbox"
# macos-14 runner 是 ARM64 的机器，编 x64 必须是交叉：
# 光给 --arch=x86_64 不够，clang 默认还是吐 arm64，configure 的存活检测直接错乱。
# 这里跟 linux-386 的 gcc-m32 同款做法：包个 -arch x86_64 的 clang 皮，
# configure 和最后链接都走它（arm64 原生走系统 cc，不动）。
MAC_CC=cc
case "$ARCH" in
  arm64) ARCHFLAG="--arch=arm64 --target-os=darwin" ;;
  x64)
    printf '#!/bin/sh\nexec cc -arch x86_64 "$@"\n' > "$BLD/clang-x64"
    chmod +x "$BLD/clang-x64"
    MAC_CC="$BLD/clang-x64"
    ARCHFLAG="--arch=x86_64 --target-os=darwin --cc=$BLD/clang-x64"
    ;;
  *) echo "unknown arch $ARCH" >&2; exit 2 ;;
esac

# mac 的 ld（这台旧版）没有等价开关，从源头治：mac 编时关掉 exr/phm
# 两个解码器（都不是看片主流，Linux 不受影响），libavcodec 不再产 half2float.o。
COMMON_MAC="$COMMON --disable-decoder=exr --disable-decoder=phm"
# shellcheck disable=SC2086
"$SRC/configure" $COMMON_MAC $FULL_DEPS_MAC $MAC_BASE $ARCHFLAG --enable-pic --disable-x86asm
make -j"$(sysctl -n hw.ncpu)"

WHOLE="-Wl,-all_load libavformat/libavformat.a libavcodec/libavcodec.a libswscale/libswscale.a libavfilter/libavfilter.a libswresample/libswresample.a libavdevice/libavdevice.a libavutil/libavutil.a"
FULL_EXT=""
if [ "$V" = "full" ]; then
  for pc in freetype2 harfbuzz fontconfig fribidi libass; do
    if pkg-config --exists "$pc" 2>/dev/null; then
      FULL_EXT="$FULL_EXT $(pkg-config --static --libs "$pc" 2>/dev/null)"
    fi
  done
  OH=$(pkg-config --static --libs openh264 2>/dev/null || true)
  FULL_EXT="$FULL_EXT $OH"
fi
# shellcheck disable=SC2086
# MULDEFS 见上：mac 关掉 exr/phm 后冲突消失，这里直接链原包。
$MAC_CC -dynamiclib -o "$OUT/$LIB" $WHOLE $FULL_EXT -lm -lpthread -ldl -lz \
  -framework VideoToolbox -framework CoreMedia -framework CoreVideo -framework Security
ls -la "$OUT/$LIB"
