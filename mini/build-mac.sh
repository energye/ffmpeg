#!/bin/sh
# mac单文件：在mac机器上跑。产物：
#   dist/darwin-arm64/libgpui_ffmpeg.dylib（M芯片）
#   dist/darwin-x64/libgpui_ffmpeg.dylib（Intel）
# 本地两个一次全编，外加一个universal二合一；CI里矩阵式各编各的
# （照 rwgpu cd.yml：在 macos-latest 上起两个任务，一个编 x86_64，
# 一个编 aarch64，不在一台上硬交叉，省得 M 机器编 Intel 包翻车）。
# 前提：brew install nasm pkg-config
# 用法（本地全量）：SRC=$PWD OUTDIR=$PWD/dist ./mini/build-mac.sh
# 用法（CI单架构）：SRC=$PWD OUTDIR=$PWD/out ./mini/build-mac.sh x86_64 darwin-x64
#   或：SRC=$PWD OUTDIR=$PWD/out ./mini/build-mac.sh aarch64 darwin-arm64
set -e
: "${SRC:?set SRC to the ffmpeg checkout dir}"
: "${OUTDIR:?set OUTDIR to the dist dir}"

common() {
  echo "--disable-everything --disable-programs --disable-doc \
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
  --enable-videotoolbox \
  --enable-hwaccel=h264_videotoolbox --enable-hwaccel=hevc_videotoolbox \
  --enable-hwaccel=mpeg2_videotoolbox --enable-hwaccel=mpeg4_videotoolbox \
  --enable-securetransport \
  --enable-pic --enable-small \
  --disable-autodetect --disable-debug"
}

build_one() {
  ARCH=$1   # aarch64（M）或 x86_64（Intel）
  TAG=$2    # darwin-arm64 或 darwin-x64
  BLD=/tmp/ffmac-$TAG
  OUT=$OUTDIR/$TAG
  mkdir -p "$BLD" "$OUT"
  cd "$BLD"
  # M 机器编 Intel 包走 clang -arch 交叉（Xcode 原生支持，编出来是真 x86_64，
  # 最后用 lipo -info 验明正身，不怕冒充）。
  HOST_ARCH=$(uname -m)
  CC_FLAGS=""
  case "$ARCH/$HOST_ARCH" in
    aarch64/arm64|x86_64/x86_64) ;;
    x86_64/arm64) CC_FLAGS="-arch x86_64" ;;
    *) echo "unsupported combo $ARCH on $HOST_ARCH" >&2; exit 2 ;;
  esac
  # shellcheck disable=SC2046
  CC="clang $CC_FLAGS" "$SRC/configure" --prefix="$OUT/prefix" $(common) \
    --arch=$ARCH --target-os=darwin
  make -j"$(sysctl -n hw.ncpu)"
  clang $CC_FLAGS -dynamiclib -o "$OUT/libgpui_ffmpeg.dylib" \
    -install_name @rpath/libgpui_ffmpeg.dylib \
    -all_load libavformat/libavformat.a \
    -all_load libavcodec/libavcodec.a \
    -all_load libswscale/libswscale.a \
    -all_load libavfilter/libavfilter.a \
    -all_load libavdevice/libavdevice.a \
    -all_load libswresample/libswresample.a \
    -all_load libavutil/libavutil.a \
    -framework CoreFoundation -framework CoreVideo -framework CoreMedia \
    -framework VideoToolbox -framework Security \
    -lm -lpthread -lz -lbz2
  ls -la "$OUT/libgpui_ffmpeg.dylib"
  # 验明正身：M 包必须是 arm64，Intel 包必须是 x86_64。
  case "$ARCH" in
    aarch64) lipo -info "$OUT/libgpui_ffmpeg.dylib" | grep -q "arm64" || { echo "arch check failed: want arm64" >&2; exit 1; } ;;
    x86_64) lipo -info "$OUT/libgpui_ffmpeg.dylib" | grep -q "x86_64" || { echo "arch check failed: want x86_64" >&2; exit 1; } ;;
  esac
}

if [ $# -eq 2 ]; then
  # CI单架构：只编指定的那份（照 rwgpu cd.yml 矩阵式）。
  build_one "$1" "$2"
  exit 0
fi
build_one aarch64 darwin-arm64
build_one x86_64 darwin-x64
lipo -create "$OUTDIR/darwin-arm64/libgpui_ffmpeg.dylib" \
  "$OUTDIR/darwin-x64/libgpui_ffmpeg.dylib" \
  -output "$OUTDIR/darwin-universal/libgpui_ffmpeg.dylib"
ls -la "$OUTDIR/darwin-universal/libgpui_ffmpeg.dylib"
