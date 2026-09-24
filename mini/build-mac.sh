#!/bin/sh
# mac单文件：在mac机器上跑。产物：
#   dist/darwin-arm64/libgpui_ffmpeg.dylib（M芯片）
#   dist/darwin-x64/libgpui_ffmpeg.dylib（Intel，在M机器上交叉编）
#   dist/darwin-universal/libgpui_ffmpeg.dylib（二合一，可选）
# 前提：brew install nasm pkg-config
# 用法：SRC=$PWD OUTDIR=$PWD/dist ./mini/build-mac.sh
set -e
: "${SRC:?set SRC to the ffmpeg checkout dir}"
: "${OUTDIR:?set OUTDIR to the dist dir}"

common() {
  echo "--disable-everything --disable-programs --disable-doc \
  --disable-avdevice --disable-avfilter --disable-network \
  --disable-encoders --disable-muxers \
  --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac \
  --enable-demuxer=mov --enable-demuxer=matroska \
  --enable-parser=h264 --enable-parser=hevc --enable-parser=aac \
  --enable-protocol=file \
  --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=aac_adtstoasc \
  --disable-hwaccels --enable-pic --enable-small \
  --disable-autodetect --disable-debug"
}

build_one() {
  ARCH=$1   # aarch64（M）或 x86_64（Intel）
  TAG=$2    # darwin-arm64 或 darwin-x64
  BLD=/tmp/ffmac-$TAG
  OUT=$OUTDIR/$TAG
  mkdir -p "$BLD" "$OUT"
  cd "$BLD"
  # shellcheck disable=SC2046
  "$SRC/configure" --prefix="$OUT/prefix" $(common) \
    --arch=$ARCH --target-os=darwin
  make -j"$(sysctl -n hw.ncpu)"
  clang -dynamiclib -o "$OUT/libgpui_ffmpeg.dylib" \
    -install_name @rpath/libgpui_ffmpeg.dylib \
    -all_load libavformat/libavformat.a \
    -all_load libavcodec/libavcodec.a \
    -all_load libswscale/libswscale.a \
    -all_load libavutil/libavutil.a \
    -framework CoreFoundation -framework CoreVideo -framework CoreMedia \
    -lm -lpthread -lz
  ls -la "$OUT/libgpui_ffmpeg.dylib"
}

build_one aarch64 darwin-arm64
build_one x86_64 darwin-x64
lipo -create "$OUTDIR/darwin-arm64/libgpui_ffmpeg.dylib" \
  "$OUTDIR/darwin-x64/libgpui_ffmpeg.dylib" \
  -output "$OUTDIR/darwin-universal/libgpui_ffmpeg.dylib"
ls -la "$OUTDIR/darwin-universal/libgpui_ffmpeg.dylib"
