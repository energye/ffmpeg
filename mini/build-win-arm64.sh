#!/bin/sh
# win-arm64单文件：用llvm-mingw在本机或CI的Linux上编（NOT in docker，
# ubuntu18容器跑不动新版llvm-mingw）。
# 用法：LLVM_MINGW=/path/to/llvm-mingw ./mini/build-win-arm64.sh
# 产物：/out/win-arm64/libgpui_ffmpeg.dll（无glibc依赖，和容器编等价）
set -e
: "${LLVM_MINGW:?set LLVM_MINGW to the unpacked llvm-mingw dir}"
: "${SRC:?set SRC to the ffmpeg checkout dir}"
: "${OUTDIR:=/tmp/ffout}"
export PATH="$LLVM_MINGW/bin:$PATH"
T=win-arm64
BLD=/tmp/b-$T
OUT=$OUTDIR/$T
mkdir -p "$BLD" "$OUT"
cd "$BLD"
"$SRC/configure" --prefix="$OUT/prefix" \
  --disable-everything --disable-programs --disable-doc \
  --disable-avdevice --disable-avfilter --disable-network \
  --disable-encoders --disable-muxers \
  --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=aac \
  --enable-demuxer=mov --enable-demuxer=matroska \
  --enable-parser=h264 --enable-parser=hevc --enable-parser=aac \
  --enable-protocol=file \
  --enable-bsf=h264_mp4toannexb --enable-bsf=hevc_mp4toannexb --enable-bsf=aac_adtstoasc \
  --disable-hwaccels --disable-x86asm --enable-pic --enable-small \
  --disable-autodetect --disable-debug \
  --enable-cross-compile --cross-prefix=aarch64-w64-mingw32- \
  --arch=aarch64 --target-os=mingw64
make -j"$(nproc)"
aarch64-w64-mingw32-gcc -shared -o "$OUT/libgpui_ffmpeg.dll" \
  -Wl,--whole-archive libavformat/libavformat.a libavcodec/libavcodec.a \
    libswscale/libswscale.a libavutil/libavutil.a -Wl,--no-whole-archive \
  -lbcrypt -lws2_32 -lm
ls -la "$OUT/libgpui_ffmpeg.dll"
