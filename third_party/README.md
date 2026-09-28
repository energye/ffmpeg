# gpui FFmpeg 构建依赖（预置源码包，离线可用）。
#
# 背景：CI 每次构建都要从上游现下这 10 个包，freedesktop.org 经常回 418
# 或反爬虫页，gitlab 镜像偶发坏包，导致构建纯因网络抖动挂掉。经用户确认，
# 把验证过的包直接存进本仓，构建时优先用本地包，不再碰外网。
#
# 包的来源（全部是各库官方，未改源码；fontconfig 例外见下）：
#   freetype-2.13.2.tar.gz   savannah 官方 release
#   harfbuzz-8.3.0.tar.xz    GitHub harfbuzz 官方 release
#   fribidi-1.0.13.tar.xz    GitHub fribidi 官方 release（v1.0.13）
#   fontconfig-2.15.0.tar.gz GitHub fontconfig/fontconfig 2.15.0
#                            （freedesktop 官网挂反爬虫，用 GitHub 镜像；
#                            源码树无 configure，构建走 meson，见下）
#   libass-0.17.1.tar.gz     GitHub libass 官方 release
#   openh264-2.4.1.tar.gz    GitHub cisco/openh264 v2.4.1（60MB，
#                            大头是 res/test 测试视频，构建用不到，
#                            后续可剥离再压一次包）
#   openssl-3.0.16.tar.gz    openssl 官网
#   zlib-1.3.1.tar.gz        GitHub madler/zlib 官方 release（v1.3.1）
#   expat-2.6.4.tar.gz       GitHub libexpat 官方 release（R_2_6_4）
#   libunibreak-8.0.tar.gz   GitHub adah1972/libunibreak（libunibreak_8_0）
#
# 用法：dual/build-deps.sh 与 dual/build-deps-mac.sh 的 need() 先找
#   本目录同名文件，有就直接用并验包；没有才走外网下载（逻辑不变，
#   本地包即第一优先级）。升级版本时把新包放进本目录并同步两处脚本
#   的默认版本号（与 dual/Dockerfile ENV 三处同步）。
#
# 许可：包本身未改动，各库许可见 dual/build-deps.sh 头注释；
# x264/x265/fdk 三个 GPL 件不在此列，构建也不开。
