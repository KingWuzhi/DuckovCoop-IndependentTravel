# 逃离鸭科夫 · 联机 Mod「独立分图版」

**把「切图必须全员投票、一起走」改成「各走各的」。**

[![上游基线](https://img.shields.io/badge/base-upstream%20v1.3.6-2ea44f?style=flat-square)](https://github.com/Mr-sans-and-InitLoader-s-team/Escape-From-Duckov-Coop-Mod-Preview)
[![本版构建](https://img.shields.io/badge/build-v1.3.6.2-2f5fe0?style=flat-square)](dist/_checksums.csv)
[![License](https://img.shields.io/badge/license-AGPL--3.0%20%2B%20restrictions-red?style=flat-square)](LICENSE_RESTRICTIONS.txt)

[English](README_EN.md) | **简体中文**

> [!WARNING]
> **这是第三方修改版，不是原作者发布的版本。**
> 原作者是 **Mr-sans-and-InitLoader-s-team**，原项目 [Escape-From-Duckov-Coop-Mod-Preview](https://github.com/Mr-sans-and-InitLoader-s-team/Escape-From-Duckov-Coop-Mod-Preview)。
> 本仓库基于其 **v1.3.6** 源码修改，**不包含上游 v1.4.x 的任何更新**，也**不发布 Steam 创意工坊条目**（工坊里那个仍是原版）。
> 使用或分发前请读 [LICENSE_RESTRICTIONS.txt](LICENSE_RESTRICTIONS.txt)：**禁止商用、禁止架设游戏服务器、分发必须署名**。

---

## 这是什么

原版联机 Mod 的切图是「全员投票通过、所有人一起进同一张图」。两个人一起玩没问题，但只要你和一个朋友想分头行动——一个去搜刮、一个去做任务——就必须互相等、互相迁就。

这个修改版把这道闸门拆了：

- **谁触发切图谁自己走**，其他人留在原地图，两边互不打断；
- 新增 `SceneStateLedger`，**按地图独立记录**门、战利品容器、可破坏物、关卡机关和付费状态；后来进入同一张图的人看到的是同样的世界，不会出现「别人开过的门在你这儿是关的」；
- 机关、战利品、AI 生成/销毁等广播**按场景过滤**，避免跨图污染；
- 玩家替身只在同图创建，异地图的人不在你本机生成。

代价是：主机不在的那张图，AI 不会动（详见 [docs/INDEPENDENT_TRAVEL.md](docs/INDEPENDENT_TRAVEL.md)）。这是当前架构的边界，不是 bug。

## 与上游 v1.3.6 的差异

| 改动 | 说明 |
| --- | --- |
| 取消全员切图投票 | 原投票代码保留但不再可达；切图只影响触发者 |
| 去掉切图时的固定等待 | 客机切图不再有约 10 秒的「等待主机完成加载」遮罩，关卡初始化直接开始 |
| 新增场景状态账本 | `SceneStateLedger`：按场景记账，进入时按场景回放已广播的世界状态 |
| 广播按场景过滤 | 机关 bool、战利品、AI 生成/销毁等只投递给同场景玩家 |
| 玩家替身仅同图创建 | 异地图的人物不在本机生成 |
| 移除「仅房主可改」的分图开关 | 该设置是 host-only 且不参与网络同步，两端读不同值会导致行为分裂 |
| 本地化补充 | 7 种语言文案增补 |

逐条改动见 [CHANGELOG.md](CHANGELOG.md)。

## 谁适合用

- ✅ **你和朋友想各干各的**：一个人跑图搜刮，一个人留在安全区整理背包。
- ✅ **你能确保所有人用同一份构建**：连接时会校验 `BuildInfo.ModVersion`，版本不一致直接拒绝入局。
- ❌ **想和创意工坊原版玩家混联**：不行，版本门槛会把你挡在外面。
- ❌ **想跟上游更新**：本仓库不跟进 v1.4.x。改动是针对 1.3.6 的代码结构做的，直接套到 1.4.x 会冲突。

## 安装（普通玩家）

游戏只从 **Steam 已订阅的创意工坊物品**里加载 Mod，`Duckov_Data\Mods` 不是加载来源，把文件丢进去不会生效——这是最容易踩的坑。

### 前置：订阅原版并让它下载完

1. 打开 Steam 创意工坊，订阅「**逃离鸭科夫联机mod**」（物品 ID `3591341282`，游戏 AppID `3167020`）；
2. **启动一次游戏**，等它把 Mod 下载完（确认 Mod 目录里出现 `info.ini`），然后退出游戏。

### 拿到这个包

两种方式，内容一样：

| 方式 | 说明 |
| --- | --- |
| **Releases 附件**（推荐） | 在仓库右侧 `Releases` 下载 `DuckovCoop-Independent-Travel-v1.3.6.2.zip` |
| **仓库里的 `dist/` 目录** | 克隆或下载仓库后，`dist/` 里就是完整安装包（安装器 + `files/`） |

### 运行安装器

1. **完全退出游戏**（Steam 可以开着）；
2. 在 `dist/` 目录打开 PowerShell：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

3. 看到「**安装完成，可以启动游戏了。**」即可。

安装器依次做这些事：

| 步骤 | 说明 |
| --- | --- |
| 备份 | 原文件复制到 `%LOCALAPPDATA%\DuckovCoopModBackup\<时间戳>\` |
| 覆盖 | 把 `files\` 里的 2 个 DLL 与 7 个语言文件写入创意工坊 Mod 目录 |
| 同步 Managed | 把 `EscapeFromDuckovModApi.dll` 复制到 `游戏目录\Duckov_Data\Managed\`（**漏这步联机会加载失败**） |
| 校验 | 逐个文件比对 SHA256 |
| 上锁 | 给这些文件加「只读 + 拒绝写入/删除」，阻止 Steam 自动更新覆盖 |

### 常用命令

| 目的 | 命令 |
| --- | --- |
| 查看是否装好、是否被 Steam 换回 | `.\install.ps1 -Action Status` |
| 重新安装 / 作者更新后再装一次 | `.\install.ps1` |
| 解锁（允许 Steam 更新） | `.\install.ps1 -Action Unlock` |
| 还原安装前的文件 | `.\install.ps1 -Action Restore` |
| 只预览、不实际改动 | 任意命令后加 `-WhatIfOnly` |
| 安装但不上锁 | 安装命令后加 `-NoLock` |

## 为什么要「上锁」

Steam **没有**「对单个创意工坊物品禁用自动更新」的开关。原作者一更新，Steam 就会把工坊里的 `EscapeFromDuckovCoopMod.dll` 换回官方版，而 `Duckov_Data\Managed` 里的 `EscapeFromDuckovModApi.dll` 还是本包的版本。两边版本对不上时，点「继续游戏」会抛 `TypeLoadException: CoopPeer`，表现为**卡在继续界面**。

所以安装器改用文件层保护：只读属性 + 拒绝 `Write`（挡覆盖写入）+ 拒绝 `Delete`（挡「下到临时文件再改名替换」）。**这不妨碍游戏读取，只妨碍写入。**

## 已知限制

1. **Steam 可能提示这个 Mod「更新失败」**——这是上锁的预期结果，不是错误。
2. **不要在这个状态下「取消订阅」**：Steam 删文件会被拒绝，留下孤立文件。要退订请先 `-Action Unlock`。
3. `Managed\EscapeFromDuckovModApi.dll` **没有上锁**（它在游戏本体目录，锁了可能影响游戏自身校验）。如果游戏本体更新重写了它，会再次版本错配，重跑安装器即可。
4. **所有联机玩家必须使用同一个包**，否则版本校验不过，表现为连不上/被踢。
5. **分图后另一张图的 AI 不动**：主机不在那张图，AI 不会在该图模拟。设计边界，不是 bug。
6. **游戏内 Mod 列表显示的版本号不是本包版本**：`info.ini` 是作者工坊条目里的原文件，为保持与工坊一致**未作改动**，里面写的是上游的版本串。判断本包版本请看 `BuildInfo.ModVersion`（当前 `1.3.6.2`）或 [dist/_checksums.csv](dist/_checksums.csv)。

## 从源码构建（开发向）

前置：

- **游戏本体**——编译需要引用 `Duckov_Data\Managed` 下的游戏程序集，这些文件受版权保护，不随仓库分发；
- **.NET 9 SDK**（解决方案按 VS 17.14 工具链编写，依赖 Polyfill 8.9.0）。

```powershell
git clone https://github.com/KingWuzhi/DuckovCoop-IndependentTravel.git
cd DuckovCoop-IndependentTravel
$env:DUCKOV_GAME_DIRECTORY = 'G:\SteamLibrary\steamapps\common\Escape from Duckov'
dotnet build EscapeFromDuckovCoopMod\EscapeFromDuckovCoopMod.csproj -c Release
```

`Directory.Build.props` 会据此推导 `Duckov_Data\Managed` 的路径。构建产物会被自动复制到 `Duckov_Data\Mods\联机Mod1\`——**但游戏不读那个目录**，需要按下面的落点手工搬，或者直接替换 `dist\files\` 里的 DLL 后跑安装器。

| 文件 | 必须放到 |
| --- | --- |
| `EscapeFromDuckovCoopMod.dll` | `...\workshop\content\3167020\3591341282\` |
| `EscapeFromDuckovModApi.dll` | 同一目录 **＋** `Duckov_Data\Managed\`（**两处必须是同一个文件**） |
| `Localization\*.json` | `...\3591341282\Localization\` |
| `info.ini` | `...\3591341282\`（作者原文件，本版未修改） |

## 仓库结构

```
EscapeFromDuckovCoopMod/          Mod 主工程（netstandard2.1）
  Main/SceneService/              场景、切图、状态账本
    SceneNet.cs                   切图流程、场景闸门、独立分图入口
    SceneStateLedger.cs           按场景记账（本版新增）
  Main/NetService.cs              连接、握手、版本门槛
  Main/Loader/Mod.cs              消息分发入口
  Patch/                          Harmony 补丁
EscapeFromDuckovModApi/           给其他 Mod 的 API 层（必须与主工程配对）
Localization/                     7 种语言 JSON
dist/                          可直接分发的安装包（安装器 + files/ + 校验和）
docs/                             设计与边界文档
```

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md) | 项目总览、原作者与授权、部署细节、排错表 |
| [docs/INDEPENDENT_TRAVEL.md](docs/INDEPENDENT_TRAVEL.md) | 独立分图的覆盖范围、实现要点与已知边界（改动前先读） |
| [CHANGELOG.md](CHANGELOG.md) | 逐条改动记录 |
| [dist/_checksums.csv](dist/_checksums.csv) | 发布包内每个文件的 SHA256 |

## 授权与署名

本项目沿用上游的 **GNU AGPLv3 + 附加限制（Section 7）**：

- [LICENSE.txt](LICENSE.txt) — AGPLv3 正文
- [LICENSE_RESTRICTIONS.txt](LICENSE_RESTRICTIONS.txt) — 附加限制
- [NOTICE-ATTRIBUTION.md](NOTICE-ATTRIBUTION.md) — 对原作者的署名声明（分发时必须随附）

必须遵守的三条：

1. ❌ **禁止商业用途**——不得收费、挂广告、以捐赠为条件提供访问，或打包进营利产品；
2. ❌ **禁止运营游戏服务器**——不得做无头中继、托管多人会话的服务端组件；
3. ✅ **必须保留显著署名**——分发时须明确标注这是对原作品的修改。

AGPLv3 要求分发修改版时提供**对应源码**：本仓库即完整源码，`dist/` 安装包对应的构建为 `v1.3.6.2`。

## 免责

修改版由社区玩家基于公开源码自行编译，**与原作者无关**，原作者不对本包的任何问题负责。联机存档请自行备份——分图玩法会让各人的进度分支更多，备份比平时更值得做。
