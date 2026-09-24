#!/bin/sh
# win-arm64单文件：用llvm-mingw在本机或CI的Linux上编（NOT in docker，
# ubuntu18容器跑不动新版llvm-mingw）。
# 用法：LLVM_MINGW=/path/to/llvm-mingw ZLIB_WINARM64=/path/to/zlib-winarm64 ./mini/build-win-arm64.sh
# ZLIB_WINARM64是给win-arm64静态编的zlib安装目录（含include/lib，默认/tmp/zlib-w64arm）
# 产物：/out/win-arm64/libgpui_ffmpeg.dll（无glibc依赖，和容器编等价）
set -e
: "${LLVM_MINGW:?set LLVM_MINGW to the unpacked llvm-mingw dir}"
: "${SRC:?set SRC to the ffmpeg checkout dir}"
: "${OUTDIR:=/tmp/ffout}"
: "${ZLIB_WINARM64:=/tmp/zlib-w64arm}"
export PATH="$LLVM_MINGW/bin:$PATH"
T=win-arm64
BLD=/tmp/b-$T
OUT=$OUTDIR/$T
mkdir -p "$BLD" "$OUT"
cd "$BLD"
"$SRC/configure" --prefix="$OUT/prefix" \
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
  --enable-demuxer=rtsp --enable-demuxer=rtp --enable-demuxer=mp3 --enable-demuxer=aac \
  --enable-demuxer=ogg --enable-demuxer=wav \
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
  --extra-cflags=-I$ZLIB_WINARM64/include --extra-ldflags=-L$ZLIB_WINARM64/lib \
  --enable-d3d11va --enable-dxva2 --enable-schannel \
  --enable-hwaccel=h264_d3d11va --enable-hwaccel=hevc_d3d11va --enable-hwaccel=vp9_d3d11va \
  --enable-hwaccel=h264_dxva2 --enable-hwaccel=hevc_dxva2 \
  --disable-x86asm --enable-pic --enable-small \
  --disable-autodetect --disable-debug \
  --enable-cross-compile --cross-prefix=aarch64-w64-mingw32- \
  --arch=aarch64 --target-os=mingw64
make -j"$(nproc)"
aarch64-w64-mingw32-gcc -shared -o "$OUT/libgpui_ffmpeg.dll" \
  -Wl,--whole-archive libavformat/libavformat.a libavcodec/libavcodec.a \
    libswscale/libswscale.a libavfilter/libavfilter.a libswresample/libswresample.a libavdevice/libavdevice.a \
    libavutil/libavutil.a -Wl,--no-whole-archive \
  $ZLIB_WINARM64/lib/libz.a -lole32 -lbcrypt -lws2_32 -lsecur32 -lm
ls -la "$OUT/libgpui_ffmpeg.dll"
