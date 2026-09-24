#!/bin/sh
# gpui最小解码单文件：编一个目标。用法：build-one.sh <linux-x64|linux-arm64|linux-386|linux-arm|win-x64>
# 产物：/out/<target>/libgpui_ffmpeg.(so|dll)
# 约定：源码挂在 /src（宿主检出目录），树外编译，源码树不脏。
# 功能清单（解码播放够用，许可保持LGPL宽松）：
#   解码 h264/hevc/aac，分流 mov(mkv在matroska里)/matroska，
#   本地文件协议，编码/推流/网络/文档全关，硬解开关先不带。
set -e
T="$1"
BLD="/tmp/b-$T"
OUT="/out/$T"
mkdir -p "$BLD" "$OUT"
cd "$BLD"

COMMON="--prefix=$OUT/prefix \
  --disable-everything --disable-programs --disable-doc \
  --disable-avdevice --disable-avfilter --disable-network \
  --disable-encoders --disable-muxers \
  --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac \
  --enable-demuxer=mov --enable-demuxer=matroska \
  --enable-parser=h264 --enable-parser=hevc --enable-parser=aac \
  --enable-protocol=file \
  --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=aac_adtstoasc \
  --disable-hwaccels --disable-x86asm --enable-pic --enable-small \
  --disable-autodetect --disable-debug"

LIB=libgpui_ffmpeg.so
case "$T" in
  linux-x64)
    CFG="$COMMON --arch=x86_64 --target-os=linux"
    CC=gcc ;;
  linux-arm64)
    CFG="$COMMON --enable-cross-compile --cross-prefix=aarch64-linux-gnu- --arch=aarch64 --target-os=linux"
    CC=aarch64-linux-gnu-gcc ;;
  linux-386)
    # configure要--cc整个一个词，用包装脚本绕开空格拆分。
    printf '#!/bin/sh\nexec gcc -m32 "$@"\n' > "$BLD/gcc-m32"
    chmod +x "$BLD/gcc-m32"
    CFG="$COMMON --arch=x86_32 --target-os=linux --cc=$BLD/gcc-m32"
    CC="$BLD/gcc-m32" ;;
  linux-arm)
    CFG="$COMMON --enable-cross-compile --cross-prefix=arm-linux-gnueabihf- --arch=arm --target-os=linux"
    CC=arm-linux-gnueabihf-gcc ;;
  win-x64)
    CFG="$COMMON --enable-cross-compile --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=mingw64"
    CC=x86_64-w64-mingw32-gcc; LIB=libgpui_ffmpeg.dll ;;
  *) echo "unknown target $T" >&2; exit 2 ;;
esac

# shellcheck disable=SC2086
/src/configure $CFG
make -j"$(nproc)"

WHOLE="-Wl,--whole-archive libavformat/libavformat.a libavcodec/libavcodec.a libswscale/libswscale.a libavutil/libavutil.a -Wl,--no-whole-archive"
case "$T" in
  win-x64)
    # shellcheck disable=SC2086
    $CC -shared -o "$OUT/$LIB" $WHOLE -lbcrypt -lws2_32 -lm
    ;;
  *)
    # -Bsymbolic：和ffmpeg官方编共享包同款做法，内部大表引用
    # 在链接时就地解决，不报重定位错。
    # shellcheck disable=SC2086
    $CC -shared -Wl,-soname,$LIB -o "$OUT/$LIB" -Wl,-Bsymbolic $WHOLE -lm -pthread
    ;;
esac
ls -la "$OUT/$LIB"
