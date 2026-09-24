#!/bin/sh
# gpui解码单文件：编一个目标。用法：build-one.sh <linux-x64|linux-arm64|linux-386|linux-arm|win-x64>
# 产物：/out/<target>/libgpui_ffmpeg.(so|dll)
# 约定：源码挂在 /src（宿主检出目录），树外编译，源码树不脏。
# 功能清单（完整播片库，许可保持LGPL宽松）：
#   解码 视频h264/hevc/vp9/av1/mpeg4/mpeg2/vp8/theora/mjpeg/vc1/wmv3/
#     dvvideo/prores/dnxhd；音频aac/mp3/opus/vorbis/flac/ac3/alac/pcm；
#     图片png/gif/webp；字幕srt/ass/webvtt。
#   分流 mov/matroska/mpegts/flv/hls/avi/asf/mpegps/image2/concat/
#     flac/ape/mpc/dts/mxf/srt/ass/webvtt/wav/ogg/mp3/aac/rtsp/rtp
#     （DASH只在x64 Linux：要libxml2，EOL源多架构装不上；
#      HLS是文本不受影响），
#   协议 本地+网络（http/https/tcp/udp/rtmp/tls…），
#   滤镜 画面（裁剪构图/帧管理/调色/老片修复/防抖/缩略图）+音频
#     （音量/混音/频谱）+硬件上下传，设备 lavfi（测试信号），
#   硬解按平台开（x64 Linux vaapi/vdpau/drm，Windows d3d11va/dxva2，
#     mac videotoolbox）。截图编码png/mjpeg/bmp/gif。编码/录制/推流全关。
set -e
T="$1"
BLD="/tmp/b-$T"
OUT="/out/$T"
mkdir -p "$BLD" "$OUT"
cd "$BLD"

COMMON="--prefix=$OUT/prefix \
  --disable-everything --disable-programs --disable-doc \
  --disable-encoders --disable-muxers \
  --enable-avdevice --enable-avfilter --enable-network \
  --enable-zlib \
  --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=vp9 --enable-decoder=av1 \
  --enable-decoder=mpeg4 --enable-decoder=mpeg2video --enable-decoder=vp8 --enable-decoder=theora \
  --enable-decoder=mjpeg --enable-decoder=vc1 --enable-decoder=wmv3 \
  --enable-decoder=dvvideo --enable-decoder=prores --enable-decoder=dnxhd \
  --enable-decoder=aac --enable-decoder=mp3 --enable-decoder=opus --enable-decoder=vorbis \
  --enable-decoder=flac --enable-decoder=ac3 --enable-decoder=alac --enable-decoder=pcm_s16le \
  --enable-decoder=png --enable-decoder=gif --enable-decoder=webp \
  --enable-decoder=srt --enable-decoder=ass --enable-decoder=webvtt \
  --enable-encoder=png --enable-encoder=mjpeg --enable-encoder=bmp --enable-encoder=gif \
  --enable-demuxer=mov --enable-demuxer=matroska --enable-demuxer=mpegts \
  --enable-demuxer=flv --enable-demuxer=hls \
  --enable-demuxer=avi --enable-demuxer=asf --enable-demuxer=mpegps \
  --enable-demuxer=image2 --enable-demuxer=concat \
  --enable-demuxer=flac --enable-demuxer=ape --enable-demuxer=mpc --enable-demuxer=dts \
  --enable-demuxer=mxf \
  --enable-demuxer=srt --enable-demuxer=ass --enable-demuxer=webvtt --enable-demuxer=wav \
  --enable-demuxer=ogg --enable-demuxer=mp3 --enable-demuxer=aac \
  --enable-demuxer=rtsp --enable-demuxer=rtp \
  --enable-parser=h264 --enable-parser=hevc --enable-parser=vp9 --enable-parser=av1 \
  --enable-parser=mpegaudio --enable-parser=opus --enable-parser=vorbis \
  --enable-parser=mpeg4video --enable-parser=mpegvideo --enable-parser=aac \
  --enable-parser=vp8 --enable-parser=mjpeg --enable-parser=png \
  --enable-protocol=file --enable-protocol=http --enable-protocol=https \
  --enable-protocol=tcp --enable-protocol=udp --enable-protocol=tls \
  --enable-protocol=data --enable-protocol=pipe --enable-protocol=cache \
  --enable-protocol=concat --enable-protocol=subfile --enable-protocol=ftp \
  --enable-protocol=rtmp \
  --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=aac_adtstoasc \
  --enable-bsf=vp9_superframe --enable-bsf=av1_frame_merge \
  --enable-bsf=extract_extradata --enable-bsf=dump_extradata \
  --enable-bsf=dts2pts --enable-bsf=noise \
  --enable-filter=crop --enable-filter=pad --enable-filter=overlay \
  --enable-filter=rotate --enable-filter=hue \
  --enable-filter=yadif --enable-filter=bwdif --enable-filter=thumbnail \
  --enable-filter=split --enable-filter=select --enable-filter=trim --enable-filter=concat \
  --enable-filter=fps --enable-filter=scale --enable-filter=format --enable-filter=transpose \
  --enable-filter=unsharp --enable-filter=gblur --enable-filter=noise --enable-filter=deband \
  --enable-filter=deshake --enable-filter=tonemap \
  --enable-filter=aresample --enable-filter=aformat \
  --enable-filter=hwupload --enable-filter=hwdownload --enable-filter=hwmap \
  --enable-filter=loudnorm --enable-filter=acompressor --enable-filter=amix --enable-filter=pan \
  --enable-filter=volume --enable-filter=showspectrum --enable-filter=volumedetect \
  --enable-filter=sine --enable-filter=anoisesrc --enable-filter=aevalsrc \
  --enable-indev=lavfi \
  --disable-x86asm --enable-pic --enable-small \
  --disable-autodetect --disable-debug"

LIB=libgpui_ffmpeg.so
# 外部库与硬解按平台开（autodetect已关，必须显式开）：
#   x64 Linux：openssl+libxml2（https/DASH）+vaapi/vdpau/drm（核显硬解）。
#     av1_vaapi除外：ubuntu18的vaapi头太老缺AV1字段，配不过（AV1照样软解）。
#   其它Linux（arm64/386/arm）：openssl（https），硬解走软解，
#     无DASH分流（见上）；HLS是文本不受影响，本地文件全能播。
#   Windows：系统schannel（TLS）+d3d11va/dxva2（系统硬解），不添第三方依赖；
#     无DASH（mingw缺libxml2，后续可源码编一个跟上），HLS照样有。
# TLS：Linux用openssl，Windows用系统schannel（不添依赖）。
FULL_LINUX="--enable-openssl --enable-libxml2 --enable-demuxer=dash --extra-libs=-ldl --extra-libs=-pthread \
  --enable-vaapi --enable-vdpau --enable-libdrm \
  --enable-hwaccel=h264_vaapi --enable-hwaccel=hevc_vaapi --enable-hwaccel=vp9_vaapi \
  --enable-hwaccel=mpeg2_vaapi --enable-hwaccel=mpeg4_vaapi"
# -ldl -pthread：静态安全库链接时要系统线程/动态加载库，不然configure试链不过。
CROSS_LINUX="--enable-openssl --extra-libs=-ldl --extra-libs=-pthread"
HW_WIN="--enable-d3d11va --enable-dxva2 --enable-schannel \
  --enable-hwaccel=h264_d3d11va --enable-hwaccel=hevc_d3d11va --enable-hwaccel=vp9_d3d11va \
  --enable-hwaccel=h264_dxva2 --enable-hwaccel=hevc_dxva2"
# openssl装到lib还是lib64按架构走（x64/arm64是lib64，386/arm是lib），现找。
ossl_lib() {
  if [ -d "$1/lib64" ]; then echo "$1/lib64"; else echo "$1/lib"; fi
}
case "$T" in
  linux-x64)
    OSSL=/opt/ossl-x64
    ZLIB=/opt/zlib-x64
    export PKG_CONFIG_PATH=$(ossl_lib $OSSL)/pkgconfig:${PKG_CONFIG_PATH:-}
    CFG="$COMMON $FULL_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --arch=x86_64 --target-os=linux"
    CC=gcc ;;
  linux-arm64)
    OSSL=/opt/ossl-arm64
    ZLIB=/opt/zlib-arm64
    # 交叉pkg-config必须只看目标架构的.pc，否则链到x64的库。
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig
    CFG="$COMMON $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=aarch64-linux-gnu- --arch=aarch64 --target-os=linux"
    CC=aarch64-linux-gnu-gcc ;;
  linux-386)
    # configure要--cc整个一个词，用包装脚本绕开空格拆分。
    printf '#!/bin/sh\nexec gcc -m32 "$@"\n' > "$BLD/gcc-m32"
    chmod +x "$BLD/gcc-m32"
    OSSL=/opt/ossl-386
    ZLIB=/opt/zlib-386
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig
    # 386只要https/HLS（无libxml2故无DASH，见Dockerfile-32）。
    CFG="$COMMON $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --arch=x86_32 --target-os=linux --cc=$BLD/gcc-m32"
    CC="$BLD/gcc-m32" ;;
  linux-arm)
    OSSL=/opt/ossl-arm
    ZLIB=/opt/zlib-arm
    export PKG_CONFIG_LIBDIR=$(ossl_lib $OSSL)/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig
    CFG="$COMMON $CROSS_LINUX --extra-cflags=-I$OSSL/include --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$(ossl_lib $OSSL) --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=arm-linux-gnueabihf- --arch=arm --target-os=linux"
    CC=arm-linux-gnueabihf-gcc ;;
  win-x64)
    OSSL=
    ZLIB=/opt/zlib-w64
    CFG="$COMMON $HW_WIN --extra-cflags=-I$ZLIB/include --extra-ldflags=-L$ZLIB/lib --enable-cross-compile --cross-prefix=x86_64-w64-mingw32- --arch=x86_64 --target-os=mingw64"
    CC=x86_64-w64-mingw32-gcc; LIB=libgpui_ffmpeg.dll ;;
  *) echo "unknown target $T" >&2; exit 2 ;;
esac

# shellcheck disable=SC2086
/src/configure $CFG
make -j"$(nproc)"

WHOLE="-Wl,--whole-archive libavformat/libavformat.a libavcodec/libavcodec.a libswscale/libswscale.a libavfilter/libavfilter.a libswresample/libswresample.a libavdevice/libavdevice.a libavutil/libavutil.a -Wl,--no-whole-archive"
case "$T" in
  win-x64)
    # Windows：系统TLS(schannel)+系统解码接口，不添第三方依赖。
    # shellcheck disable=SC2086
    $CC -shared -o "$OUT/$LIB" $WHOLE $ZLIB/lib/libz.a -lole32 -lbcrypt -lws2_32 -lsecur32 -lm
    ;;
  *)
    # Linux：安全库静态打进so（/opt/ossl-*，不欠动态账，在哪台机器都打得开）；
    # libxml2/vaapi/vdpau/drm动态链（x64；目标机需装运行时库，通常桌面自带，
    # 缺则Dlopen失败——真机验证时先查 ldd）。
    # -Bsymbolic：和ffmpeg官方编共享包同款做法，内部大表引用
    # 在链接时就地解决，不报重定位错。
    # 注意：交叉目标只有静态安全库，va/xml2那套只在x64开，
    # 这里按目标分链接库。
    # shellcheck disable=SC2086
    case "$T" in
      linux-x64)
        $CC -shared -Wl,-soname,$LIB -o "$OUT/$LIB" -Wl,-Bsymbolic $WHOLE -lm -pthread $(ossl_lib $OSSL)/libssl.a $(ossl_lib $OSSL)/libcrypto.a $ZLIB/lib/libz.a -ldl -lxml2 -lva -lva-drm -lvdpau -ldrm
        ;;
      *)
        $CC -shared -Wl,-soname,$LIB -o "$OUT/$LIB" -Wl,-Bsymbolic $WHOLE -lm -pthread $(ossl_lib $OSSL)/libssl.a $(ossl_lib $OSSL)/libcrypto.a -ldl $ZLIB/lib/libz.a
        ;;
    esac
    ;;
esac
ls -la "$OUT/$LIB"
