#!/bin/sh
# gpui 双版本单文件：编一个目标的一个版本。
# 用法：build-one.sh <linux-x64|linux-arm64|linux-386|linux-arm|win-x64|win-arm64> <base|full>
# 产物：/out/<target>/libgpui_ffmpeg.(so|dll)（基础版）或
#       /out/<target>/libgpui_ffmpeg_full.(so|dll)（高级版）
# 约定：源码挂在 /src（宿主检出目录），树外编译，源码树不脏。
# 配方唯一真源：本仓 dual/recipe（Go 命令），这里只管拼平台部分，
# 功能开关由 recipe 吐出（$RECIPE_FLAGS），本脚本不再手写 --enable-* 名单。
# 许可：两档都不碰 GPL（x264/x265/fdk 一个不开），LGPL 2.1 不变。
set -e
T="$1"
V="${2:-base}"
BLD="/tmp/b-$T-$V"
OUT="/out/$T"
mkdir -p "$BLD" "$OUT"
cd "$BLD"

# 配方从本仓 dual/recipe 工具取（由 workflow 传进来，见 /tmp/recipe-$V.flags）。
# 本地跑：先在 ffmpeg 仓根下 cd dual && go run ./recipe -variant $V > /tmp/recipe-$V.flags
if [ -n "$RECIPE_FLAGS" ]; then
  COMMON="$RECIPE_FLAGS"
elif [ -f "/tmp/recipe-$V.flags" ]; then
  COMMON=$(cat "/tmp/recipe-$V.flags")
else
  echo "RECIPE_FLAGS 未设置且 /tmp/recipe-$V.flags 不存在" >&2
  echo "先跑：cd dual && go run ./recipe -variant $V > /tmp/recipe-$V.flags" >&2
  exit 2
fi

# 高级版外库（BSD/LGPL/ISC，许可干净，全静态打进单文件）：
# freetype+harfbuzz（drawtext 必须）+ fontconfig+fribidi（建议，中东文字排版）
# + libass（subtitles/ass 必须）+ openh264（H264 编码，BSD）。
# 基础版不加这段，零外库。
# 外库来源二选一（都静态 .a + -fPIC）：
#   A. 容器内 apt 装 -dev 包（编完即验，网络要通外网）；
#   B. 预置源码包（/tmp/deps/*.tar.*，离线可编，见 build-deps.sh）。
# 各 /opt/<name>-<arch> 由 Dockerfile 或 build-deps.sh 预装。
# 容错：哪个外库的 pkg-config 找不到，就自动丢掉对应 --enable 开关并告警，
# 本次编出“缺啥少啥”的 full（复用+原生编码一定在，烧字看命），
# 不让一次缺料卡死整版。Actions 上料全时自然是完整 full。
FULL_DEPS_LINUX=""
FULL_DROP=""
if [ "$V" = "full" ]; then
  # 先把当前目标的外库 .pc 目录加进搜索路径（不存在的目录会被忽略）。
  # 注意：只加当前目标的后缀，不加全套——win 下要是把 linux-x64 的
  # .pc 混进来，pkg-config 会误判库存在，configure 拿 linux 的 .a
  # 去给 mingw 用，直接报错（实测 win-x64 full 挂在 libass 上）。
  # case 分支里的按目标追加只是去重兜底。
  case "$T" in
    linux-x64) DETSFX=x64 ;; linux-arm64) DETSFX=arm64 ;;
    linux-386) DETSFX=386 ;; linux-arm) DETSFX=arm ;;
    win-x64) DETSFX=w64 ;; win-arm64) DETSFX=w64arm ;;
    *) DETSFX="" ;;
  esac
  if [ -n "$DETSFX" ]; then
    for d in freetype harfbuzz fontconfig fribidi ass openh264 expat zlib; do
      export PKG_CONFIG_PATH="/opt/$d-$DETSFX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    done
  fi
  want_pc="libfreetype:freetype2 libharfbuzz:harfbuzz libfontconfig:fontconfig libfribidi:fribidi libass:libass libopenh264:openh264"
  for pair in $want_pc; do
    lib="${pair%%:*}"; pc="${pair##*:}"
    if pkg-config --exists "$pc" 2>/dev/null; then
      FULL_DEPS_LINUX="$FULL_DEPS_LINUX --enable-$lib"
    else
      echo "WARN: 缺外库 $pc，丢掉 --enable-$lib（本次 full 无此功能）" >&2
      FULL_DROP="$FULL_DROP --enable-$lib"
    fi
  done
  # 连带滤镜：subtitles/ass 要 libass；drawtext 要 freetype+harfbuzz。
  # 缺库时把对应 --enable-filter= 一起丢掉，否则 configure 直接报错退出。
  case "$FULL_DROP" in
    *--enable-libass*) FULL_DROP="$FULL_DROP --enable-filter=subtitles --enable-filter=ass" ;;
  esac
  case "$FULL_DROP" in
    *--enable-libfreetype*|*--enable-libharfbuzz*) FULL_DROP="$FULL_DROP --enable-filter=drawtext" ;;
  esac
  # 从配方 COMMON 里剔掉丢弃项（配方是意愿，实际以本机料为准）。
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
    echo "WARN: 本次 full 丢掉:$FULL_DROP" >&2
  fi
fi

LIB=libgpui_ffmpeg.so
if [ "$V" = "full" ]; then
  LIB=libgpui_ffmpeg_full.so
fi
# 外部库与硬解按平台开（autodetect已关，必须显式开）：
#   x64 Linux：openssl+libxml2（https/DASH）+vaapi/vdpau/drm（核显硬解）。
#   其它Linux（arm64/386/arm）：openssl（https），硬解走软解。
#   Windows：系统schannel（TLS）+d3d11va/dxva2（系统硬解），不添第三方依赖。
FULL_LINUX="--enable-openssl --enable-libxml2 --enable-demuxer=dash --extra-libs=-ldl --extra-libs=-pthread \
  --enable-vaapi --enable-vdpau --enable-libdrm \
  --enable-hwaccel=h264_vaapi --enable-hwaccel=hevc_vaapi --enable-hwaccel=vp9_vaapi \
  --enable-hwaccel=mpeg2_vaapi --enable-hwaccel=mpeg4_vaapi"
CROSS_LINUX="--enable-openssl --extra-libs=-ldl --extra-libs=-pthread"
HW_WIN="--enable-d3d11va --enable-dxva2 --enable-schannel \
  --enable-hwaccel=h264_d3d11va --enable-hwaccel=hevc_d3d11va --enable-hwaccel=vp9_d3d11va \
  --enable-hwaccel=h264_dxva2 --enable-hwaccel=hevc_dxva2"
ossl_lib() {
  if [ -d "$1/lib64" ]; then echo "$1/lib64"; else echo "$1/lib"; fi
}
# 外库头文件与静态库路径（高级版用，基础版忽略）。
# 约定 /opt/<name>-<suffix>，suffix 与目标对应（x64/arm64/386/arm/w64）。
dep_flags() { # $1=小写名 $2=目录
  if [ -d "$2" ]; then
    echo "--extra-cflags=-I$2/include --extra-ldflags=-L$2/lib"
  fi
}
case "$T" in
  linux-x64)
    OSSL=/opt/ossl-x64
    ZLIB=/opt/zlib-x64
    export PKG_CONFIG_PATH=$(ossl_lib $OSSL)/pkgconfig:${PKG_CONFIG_PATH:-}
    if [ "$V" = "full" ]; then
      for d in freetype harfbuzz fontconfig fribidi ass openh264 expat; do
        export PKG_CONFIG_PATH="/opt/$d-x64/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
      done
    fi
    CFG="$COMMON $FULL_DEPS_LINUX $FULL_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --arch=x86_64 --target-os=linux"
    CC=gcc ;;
  linux-arm64)
    OSSL=/opt/ossl-arm64
    ZLIB=/opt/zlib-arm64
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig
    if [ "$V" = "full" ]; then
      # freetype2 的 .pc 写了 Requires: zlib，搜索路径必须带上自建 zlib-$TAG，
      # 否则 libass 的传递依赖解析直接炸（实测 arm64/arm 全挂在 libass 检测上）。
      for d in freetype harfbuzz fontconfig fribidi ass openh264 expat zlib; do
        PKG_CONFIG_LIBDIR="/opt/$d-arm64/lib/pkgconfig:${PKG_CONFIG_LIBDIR:-}"
      done
      export PKG_CONFIG_LIBDIR
    fi
    CFG="$COMMON $FULL_DEPS_LINUX $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=aarch64-linux-gnu- --arch=aarch64 --target-os=linux"
    CC=aarch64-linux-gnu-gcc ;;
  linux-386)
    # 386 用独立交叉包（不用 -m32，见 Dockerfile 注释）。
    OSSL=/opt/ossl-386
    ZLIB=/opt/zlib-386
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig
    if [ "$V" = "full" ]; then
      for d in freetype harfbuzz fontconfig fribidi ass openh264 expat zlib; do
        PKG_CONFIG_LIBDIR="/opt/$d-386/lib/pkgconfig:${PKG_CONFIG_LIBDIR:-}"
      done
      export PKG_CONFIG_LIBDIR
    fi
    CFG="$COMMON $FULL_DEPS_LINUX $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=i686-linux-gnu- --arch=x86_32 --target-os=linux"
    CC=i686-linux-gnu-gcc ;;
  linux-arm)
    OSSL=/opt/ossl-arm
    ZLIB=/opt/zlib-arm
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig
    if [ "$V" = "full" ]; then
      for d in freetype harfbuzz fontconfig fribidi ass openh264 expat zlib; do
        PKG_CONFIG_LIBDIR="/opt/$d-arm/lib/pkgconfig:${PKG_CONFIG_LIBDIR:-}"
      done
      export PKG_CONFIG_LIBDIR
    fi
    CFG="$COMMON $FULL_DEPS_LINUX $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=arm-linux-gnueabihf- --arch=arm --target-os=linux"
    CC=arm-linux-gnueabihf-gcc ;;
  win-x64)
    ZLIB=/opt/zlib-w64
    # Windows 高级版烧字：mingw 静态链（freetype+harfbuzz+fontconfig+
    # fribidi+libass+openh264，见 build-deps.sh w64），与 linux/mac 对齐。
    CFG="$COMMON $FULL_DEPS_LINUX $HW_WIN --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=mingw64"
    CC=x86_64-w64-mingw32-gcc; LIB="libgpui_ffmpeg.dll"
    if [ "$V" = "full" ]; then LIB="libgpui_ffmpeg_full.dll"; fi ;;
  win-arm64)
    ZLIB=/opt/zlib-w64arm
    # win-arm64 必须真 ARM64：用 llvm-mingw 的 clang（x86_64 mingw 打不出
    # arm64，之前复用 x86_64 前缀是错的，已拆开）。烧字静态链同 w64。
    CFG="$COMMON $FULL_DEPS_LINUX $HW_WIN --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=aarch64-w64-mingw32- --arch=aarch64 --target-os=mingw64 --cc=aarch64-w64-mingw32-clang"
    CC=aarch64-w64-mingw32-clang; LIB="libgpui_ffmpeg.dll"
    if [ "$V" = "full" ]; then LIB="libgpui_ffmpeg_full.dll"; fi ;;
  *) echo "unknown target $T" >&2; exit 2 ;;
esac

# 静态链：configure 的库存活检测加 --static（只取 Libs 的话，静态
# fontconfig 因缺 expat 符号被误判为不存在；ffmpeg 官方做法，见 configure
# 里的 "When building a static binary" 提示）。
# 最终链接本来就是手拼 .a（下面的 WHOLE/FULL_EXT），这里只影响检测编译。
CFG="$CFG --pkg-config-flags=--static"
# 交叉编译（arm64/arm/win）时 configure 会去找 "<前缀>pkg-config"
#（比如 aarch64-linux-gnu-pkg-config），镜像里没有就回退成 false，
# 所有外库检测直接全灭（实测 arm64/arm 料全备好却报 libass not found，
# 日志里 WARNING: aarch64-linux-gnu-pkg-config not found）。
# 显式钉回系统 pkg-config，搜索路径走上面的 PKG_CONFIG_LIBDIR（全是目标架构的 .pc）。
CFG="$CFG --pkg-config=pkg-config"
# 动 configure 前先报料：各外库 .pc 版本与 Libs，一眼看出谁缺谁错。
echo "=== pkg-config diag ==="
for pc in freetype2 harfbuzz harfbuzz-subset fontconfig fribidi libass openh264; do
  echo "--- $pc: ver=[$(pkg-config --modversion "$pc" 2>&1 || true)] libs=[$(pkg-config --static --libs "$pc" 2>&1 || true)]"
done
trap 'rc=$?; if [ $rc -ne 0 ]; then echo "=== config.log require lines ==="; grep -a "require_pkg_config\|^ERROR" ffbuild/config.log 2>/dev/null | tail -8 || true; echo "=== config.log tail ==="; tail -c 6000 ffbuild/config.log 2>/dev/null || true; fi' EXIT
# shellcheck disable=SC2086
/src/configure $CFG
make -j"$(nproc)"

WHOLE="-Wl,--whole-archive libavformat/libavformat.a libavcodec/libavcodec.a libswscale/libswscale.a libavfilter/libavfilter.a libswresample/libswresample.a libavdevice/libavdevice.a libavutil/libavutil.a -Wl,--no-whole-archive"
# MULDEFS: exr 解码器把 half2float.o 带进 libavcodec，和 libswscale 自带的
# 同名文件重复定义（内容一样）。--whole-archive 下两份都进包，ld 默认报错，
# 加 allow-multiple-definition 取第一份（ffmpeg 官方单文件同款做法）。
MULDEFS="-Wl,--allow-multiple-definition"
# FULL_EXT: 高级版外库链接（全静态 .a 打进单文件，用户机器不用装）。
# 用 pkg-config --static 取静态链（含传递依赖），openh264 直接链 .a。
FULL_EXT=""
if [ "$V" = "full" ]; then
  case "$T" in
    win-x64) OHSFX=w64 ;; win-arm64) OHSFX=w64arm ;;
    linux-x64) OHSFX=x64 ;; linux-arm64) OHSFX=arm64 ;;
    linux-386) OHSFX=386 ;; linux-arm) OHSFX=arm ;;
    *) OHSFX=x64 ;;
  esac
  FULL_PC=""
  for pc in freetype2 harfbuzz fontconfig fribidi libass; do
    if pkg-config --exists "$pc" 2>/dev/null; then
      FULL_PC="$FULL_PC $(pkg-config --static --libs "$pc" 2>/dev/null)"
    fi
  done
  FULL_OH=""
  if [ -f "/opt/openh264-$OHSFX/lib/libopenh264.a" ]; then
    FULL_OH="/opt/openh264-$OHSFX/lib/libopenh264.a"
  fi
  FULL_EXT="$FULL_PC $FULL_OH"
  case "$T" in
    win-*) FULL_EXT="$FULL_EXT -lstdc++" ;; # mingw 链 C++ 静态库要显式带标准库。
  esac
fi
case "$T" in
  win-x64|win-arm64)
    # shellcheck disable=SC2086
    $CC -shared -o "$OUT/$LIB" $WHOLE $MULDEFS $FULL_EXT $ZLIB/lib/libz.a -static-libgcc -static-libstdc++ -lole32 -lbcrypt -lws2_32 -lsecur32 -lm
    ;;
  *)
    case "$T" in
      linux-x64)
        $CC -shared -Wl,-soname,$LIB -o "$OUT/$LIB" -Wl,-Bsymbolic $WHOLE $MULDEFS $FULL_EXT -lm -pthread $(ossl_lib $OSSL)/libssl.a $(ossl_lib $OSSL)/libcrypto.a $ZLIB/lib/libz.a -ldl -lxml2 -lva -lva-drm -lvdpau -ldrm
        ;;
      *)
        $CC -shared -Wl,-soname,$LIB -o "$OUT/$LIB" -Wl,-Bsymbolic $WHOLE $MULDEFS $FULL_EXT -lm -pthread $(ossl_lib $OSSL)/libssl.a $(ossl_lib $OSSL)/libcrypto.a -ldl $ZLIB/lib/libz.a
        ;;
    esac
    ;;
esac
ls -la "$OUT/$LIB"
# 门禁：高级版必须含写盒+编码+烧字（缺一个就报错，不让“缺啥少啥”混入库）。
if [ "$V" = "full" ]; then
  case "$T" in
    win-x64) tmp_tool="x86_64-w64-mingw32-nm" ;;
    win-arm64) tmp_tool="aarch64-w64-mingw32-nm" ;;
    *) tmp_tool="nm" ;;
  esac
  case "$T" in
    win-*)
      # 注意：DLL 没有 ELF 动态符号表，nm -D 报 no symbols，
      # 必须用不带 -D 的 nm 查（Linux .so 才用 -D）。
      fail=0
      for sym in av_muxer_iterate ff_vf_drawtext ff_vf_subtitles ff_vf_ass ff_libopenh264_encoder ff_ass_encoder; do
        if ! $tmp_tool --defined-only "$OUT/$LIB" 2>/dev/null | grep -q "$sym"; then
          echo "FAIL: full 版缺 $sym（写盒/烧字/openh264 未全进）" >&2; fail=1
        fi
      done
      if [ "$fail" != "0" ]; then exit 1; fi
      echo "PASS: full 门禁（写盒+烧字三滤镜+openh264+ass 编码全在）"
      ;;
    *)
      fail=0
      if ! $tmp_tool -D --defined-only "$OUT/$LIB" 2>/dev/null | grep -q "av_muxer_iterate"; then
        echo "FAIL: full 版缺 av_muxer_iterate 符号" >&2; fail=1
      fi
      for sym in ff_vf_drawtext ff_vf_subtitles ff_vf_ass ff_libopenh264_encoder ff_ass_encoder; do
        if ! $tmp_tool --defined-only "$OUT/$LIB" 2>/dev/null | grep -q "$sym"; then
          echo "FAIL: full 版缺 $sym（烧字/openh264 未全进）" >&2; fail=1
        fi
      done
      if [ "$fail" != "0" ]; then exit 1; fi
      echo "PASS: full 门禁（写盒+烧字三滤镜+openh264+ass 编码全在）"
      ;;
  esac
fi
