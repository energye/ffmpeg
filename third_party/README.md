# gpui FFmpeg 构建依赖（预置源码包，离线可用）。
#
# 背景：CI 每次构建都要从上游现下这 10 个包，freedesktop.org 经常回 418
# 或反爬虫页，gitlab 镜像偶发坏包，导致构建纯因网络抖动挂掉。经用户确认，
# 把验证过的包直接存进本仓，构建时优先用本地包，不再碰外网。
#
# 包的来源（全部是各库官方，未改源码）：
#   freetype-2.14.3.tar.gz   savannah 官方 release
#   harfbuzz-14.5.0.tar.xz   GitHub harfbuzz 官方 release
#   fribidi-1.0.17.tar.xz    GitHub fribidi 官方 release（v1.0.17）
#   fontconfig-2.18.3.tar.gz GitHub fontconfig/fontconfig 2.18.3
#                            （纯源码树，无 configure，构建走 meson）
#   libass-0.17.5.tar.gz     GitHub libass 官方 release
#   openh264-2.6.0.tar.gz    GitHub cisco/openh264 v2.6.0（60MB，
#                            大头是 res/test 测试视频，构建用不到）
#   openssl-3.5.8.tar.gz     GitHub openssl 官方 release（openssl-3.5.8，
#                            3.5 长期支持线；不用 4.0，版本号宏体系变了）
#   zlib-1.3.2.tar.gz        GitHub madler/zlib 官方 release（v1.3.2）
#   expat-2.8.5.tar.gz       GitHub libexpat 官方 release（R_2_8_5）
#   libunibreak-8.0.tar.gz   GitHub adah1972/libunibreak（libunibreak_8_0）
#   Python-3.11.16.tar.xz    python.org 官方（Dockerfile 里源码编，
#                            bionic 自带 python3.6 跑不动新 meson）
#   llvm-mingw-20230320.tar.xz
#                            GitHub mstorsjo/llvm-mingw 20230320
#                            （msvcrt-ubuntu-18.04-x86_64，最后一个带
#                            18.04 包的版本；新版只要 22.04 包，
#                            glibc 2.35 在 18.04 容器里跑不起来）
#
# 用法：dual/build-deps.sh 与 dual/build-deps-mac.sh 的 need() 先找
#   本目录同名文件，有就直接用并验包；没有才走外网下载（逻辑不变，
#   本地包即第一优先级）。升级版本时把新包放进本目录并同步两处脚本
#   的默认版本号（与 dual/Dockerfile ENV 三处同步）。
#
# 许可：包本身未改动，各库许可见 dual/build-deps.sh 头注释；
# x264/x265/fdk 三个 GPL 件不在此列，构建也不开。
