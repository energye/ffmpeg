# mini 解码单文件 Actions 调试计划

> 这份文档是开工单，新会话照着它干。只在 GitHub Actions 上调，不在本地编。

## 1. 背景

- 库：`/home/yanghy/app/projects/gogpu/ffmpeg`，ffmpeg 7.1.5 同一棵树，远端 `energye/ffmpeg`（公开库）。
- 产物：给 gpui video 用的单文件，两个版本都要能编出来，许可都保持 LGPL 宽松：
  基础版 `libgpui_ffmpeg.(so|dll|dylib)` 只管看（解码+分流+滤镜，编码/复用全关）；
  高级版 `libgpui_ffmpeg_full.(so|dll|dylib)` 在基础版上加写文件（复用+原生编码+烧字，x264/x265/fdk 三个 GPL 件一个不开）。
- 基础版功能清单见 `mini/build-one.sh` 开头注释：约 30 种解码、约 20 种分流（DASH 只在 x64 Linux）、网络协议、画面/音频滤镜、截图编码，硬解按平台开。
- 两档配方与构建脚本已搬进本仓 `dual/`（recipe + build-deps + build-one + Dockerfile + go.mod），本仓自己就能编两个版本；`mini/` 最小版和发版流程不动。

## 2. 目标清单（8 架构 × 2 版本 = 16 个输出）

- linux-x64、linux-arm64、linux-386、linux-arm
- win-x64、win-arm64
- darwin-x64、darwin-arm64（另有发版时二合一的 universal 包，调通两个单架构后再合）
- 每个架构编两个版本：base（基础版）+ full（高级版）
- Windows 32 位这次不做。

## 3. 调法：打标签触发，一次一个

- 调试工作流：`.github/workflows/debug-mini.yml`（带版本维度，读标签里的 base/full）。
- 发版工作流：`.github/workflows/build-mini.yml` 不动，16 个输出全绿后再把 `dual/` 合进去统一发版。
- 触发规矩（三条，互不串门）：
  平时提交代码（分支 push）谁也不触发；
  打 `debug-mini-*` 标签只触发调试流；
  发 release 只触发发版流。
- 标签格式：`debug-mini-<目标>-<版本>-<重试号>`，例如 `debug-mini-linux-x64-base-001`、`debug-mini-linux-x64-full-001`。
  同名标签推不上去，重试必须把尾巴数字加一。
- 标签里写哪个目标，Actions 就只编哪个：
  linux-/win- 开头跑 ubuntu-22.04，darwin- 开头跑 macos-latest。
- Linux 约束：ubuntu18 容器里编（老 glibc 兼容），openssl+zlib 静态打进包，不欠动态账。

## 4. 顺序

先调 Linux x64 的 base 版，调通再调同架构的 full 版，再下一个架构。建议顺序：
linux-x64-base → linux-x64-full → linux-arm64-base/full → linux-386-base/full → linux-arm-base/full → win-x64-base/full → win-arm64-base/full → darwin-arm64-base/full → darwin-x64-base/full。

## 5. 每一轮固定四步

1. 改代码（只改本次目标相关的文件）。
2. 推送到远端（提交前 `git status` 只加本次文件，不加别的；分支推送不触发任何工作流，放心推）。
3. 打标签并推送标签（推送要登录，暂由用户执行），例如：
   `git tag debug-mini-linux-x64-base-001 && git push origin debug-mini-linux-x64-base-001`
4. 等 Actions 跑完，看日志修问题，修完重试号加一再打标签。
   过线标准：base 版解码器在、能看片；full 版写盒+烧字三滤镜+openh264+ass 编码全在；
   两档都不能含 x264/x265/fdk 字样（工作流里有门禁，缺一项就算红）。

调试时不用保留中间产物，产物只要编出来、校验存在就行；最终发版时统一整合。

## 6. 看日志的方法

- 公开库不用 token 就能看：Actions 页面点进那次运行，看红的是哪一步；
  或者调 `api.github.com/repos/energye/ffmpeg/actions/runs` 查状态和结论。
- 完整报错文本需要从网页上复制，或者配一个能读 Actions 的 token 后用接口拉。

## 7. 当前状态（2026-09-28，16 个输出已全绿）

- 调试流最终绿标签：linux-x64-base-003、linux-x64-full-001、linux-arm64-base/full-001、
  linux-386-base/full-001、linux-arm-base/full-001、win-x64-base-001、win-x64-full-002、
  win-arm64-base/full-001、darwin-arm64-base-009、darwin-arm64-full-001、
  darwin-x64-base-001、darwin-x64-full-033。
- mac x64-full 是最难的一块（arm64 runner 上交叉编 x86_64），关键修复都在
  `dual/build-deps-mac.sh`（x86_64 源码静态链：freetype 关 brotli、harfbuzz 合并
  `-Dcpp_args`、fontconfig 绕开 arm64 json-c 只装 src+头+手补 `.pc` 并补 expat、
  自建 libunibreak 8.0、openh264 `.pc` 补 `-lc++`）和 `dual/build-one-mac.sh`
 （编前 `.pc` 诊断、失败吐 config 尾）。
- 下一步：按第 3 节，把 `dual/` 接进发版流 `build-mini.yml`（16 个一次编完随
  release 发布），`mini/` 最小版到时再定去留。
