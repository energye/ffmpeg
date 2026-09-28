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

- 调试工作流（三份，调哪个平台启用哪个，别的停掉）：
  `.github/workflows/debug-linux.yml` ← `debug-mini-linux-*`，
  `.github/workflows/debug-win.yml` ← `debug-mini-win-*`，
  `.github/workflows/debug-macos.yml` ← `debug-mini-darwin-*`。
  开关：`gh workflow disable/enable <文件名>`（或网页 Settings → Actions）。
- 发版工作流：`.github/workflows/release.yml`（唯一构建入口），调通后把
  验证过的步骤原样搬进去统一发版，平时不动。
- 触发规矩（三条，互不串门）：
  平时提交代码（分支 push）谁也不触发；
  打 `debug-mini-*` 标签只触发调试流；
  发 release 只触发发版流。
- 标签格式：`debug-mini-<目标>-<版本>-<重试号>`，例如 `debug-mini-linux-x64-base-001`、`debug-mini-linux-x64-full-001`。
  同名标签推不上去，重试必须把尾巴数字加一。
- 标签里写哪个目标，Actions 就只编哪个：
  linux-/win- 开头跑 ubuntu，darwin- 开头跑 macos（runner 都用 latest）。
- Linux 约束：ubuntu18 容器里编（glibc 2.27，老系统兼容），openssl+zlib 静态打进包，不欠动态账。

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

## 7. 当前状态（2026-09-28，新基座+新依赖已进仓，逐平台重验中）

- 旧基座旧依赖的绿标签：linux-x64-base-003、linux-x64-full-001/002、
  linux-arm64/386/arm-full-002、win-x64-base-001、win-x64-full-002/006、
  win-arm64-base/full-001、darwin-arm64-base-009、darwin-arm64-full-001/002、
  darwin-x64-base-001、darwin-x64-full-033/034。
- 调试流三份（调哪个平台启用哪个）：`debug-linux.yml`、`debug-win.yml`、
  `debug-macos.yml`，标签规则不变（`debug-mini-<目标>-<版本>-<重试号>`）。
- 唯一构建入口：`.github/workflows/release.yml`（release published + 手动触发），
  一次编出 8 架构 × 2 版本 = 16 个单文件 + darwin 通用包（base/full 各一），
  随 release 自动上传（publish 口径照 rwgpu cd.yml：分组 job + artifact +
  softprops/action-gh-release）。runner 全 latest，checkout 统一 v7。
- 平台分工：linux-* 与 win-*（mingw/llvm-mingw 交叉）在 ubuntu18 容器里编；
  darwin-* 在 macos 原生编，部署目标 10.15。win-full 烧字已与 linux/mac 对齐
  （w64/w64arm 烧字静态链见 `dual/build-deps.sh`，终链与门禁见 `dual/build-one.sh`）。
- 依赖预置在仓：`third_party/` 存 10 个验证过的源码包（约 100MB）+ Python 3.11 +
  llvm-mingw 20230320 + 离线 apt/pypi 包（见 README），`need()` 本地优先，
  CI 不再碰外网；升级版本时换包并同步三处版本号（Dockerfile ENV、
  build-deps 默认值、`third_party` 包，mac 脚本的 brew 行另算）。
- `mini/` 最小版和旧发版逻辑已由 `dual/` 取代，到时再定去留。
- 待办（§8 实施中）：ubuntu18 基座 + 新依赖上 CI 后，按 §4 顺序逐平台打标签
  验证（linux-x64-full 先行），三平台 16 个全绿再合入 `release.yml` 收尾。

## 8. 新需求（构建基座与依赖升级，用户已确认，一起上）

- runner 全部用最新：`ubuntu-latest`、`windows-latest`（将来真上原生时用）、
  `macos-latest`。构建实际发生在 docker 容器里，runner 版本不影响产物。
- linux 构建基座：`dual/Dockerfile` 换 `ubuntu:18.04`（源走 old-releases），
  产物最低跑 glibc 2.27（Ubuntu 18.04 / CentOS 8 / Debian 10 一代）。
- mac 部署目标：`MACOSX_DEPLOYMENT_TARGET=10.15`（原 10.13）。
- 第三方依赖升到"最新且支持 FFmpeg 7.1"的版本（与 Dockerfile ENV、
  build-deps 默认值、`third_party` 包三处同步）：

  | 包 | 旧 | 新 | 备注 |
  |---|---|---|---|
  | freetype | 2.13.2 | 2.14.3 | savannah 最新稳定，纯 C |
  | harfbuzz | 8.3.0 | 14.5.0 | meson ≥0.60，C++11；icu 继续关 |
  | fribidi | 1.0.13 | 1.0.17 | meson ≥0.54 |
  | fontconfig | 2.15.0 | 2.18.3 | 要 meson ≥1.11，只有 meson 构建；brew arm64 瓶同为 2.18.3 |
  | libass | 0.17.1 | 0.17.5 | nasm 缺失只是警告降级；`USE_ASM=No` 口径不变 |
  | openh264 | 2.4.1 | 2.6.0 | 纯 Makefile 工程 |
  | openssl | 3.0.16 | 3.5.x | 不用 4.0（版本号宏体系变了，7.1 的 tls_openssl.c 未验证）；3.5 是长期支持线 |
  | zlib | 1.3.1 | 1.3.2 | 小版本 |
  | expat | 2.6.4 | 2.8.5 | 纯 C |
  | libunibreak | 8.0 | 8.0 | 已是最新，不动 |

- ubuntu18 官方源的 meson 太老，Dockerfile 里改 pip 装新 meson+ninja；
  nasm、pkg-config、交叉工具链走 old-releases。
- llvm-mingw 上游已无 18.04 包，换最新版的 `ubuntu-22.04` 包（静态自包含，
  在 18.04 容器里照跑），`LLVM_MINGW_VER` 同步升级。
- 实施顺序：先改 Dockerfile 和版本号 → 推 `debug-mini-linux-x64-full` 验证 →
  按 §4 顺序逐平台调绿 → 全绿后合入 `release.yml`。
