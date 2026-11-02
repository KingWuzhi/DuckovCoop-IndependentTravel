# 逃离鸭科夫联机 Mod「独立分图版」— 项目总览

本仓库是《逃离鸭科夫》（Escape from Duckov）联机 Mod 的一个**第三方修改版**，基于上游 **v1.3.6** 的源码，把「切图必须全员投票、一起走」改成**「各走各的（独立分图）」**。

| | |
|---|---|
| **本仓库** | https://github.com/KingWuzhi/DuckovCoop-IndependentTravel |
| **上游原始项目** | https://github.com/Mr-sans-and-InitLoader-s-team/Escape-From-Duckov-Coop-Mod-Preview |
| **本版基线** | 上游 `v1.3.6`（commit `65d13a9`） |
| **授权** | GNU AGPLv3 + 附加限制（Section 7） |

**分支说明**

- `master` — 独立分图版（本仓库的正式内容）
- `feat/remove-scene-gate-wait` — 去掉客机切图时固定的 10 秒等待，**未合并**，处于实测阶段

> ⚠️ 上游现已发布到 `v1.4.6`，**本仓库不含 v1.4.x 的任何改动**。这是有意的：改动针对 1.3.6 的代码结构，直接套到 1.4.x 上会冲突。将来若要跟进上游，需要把 `docs/INDEPENDENT_TRAVEL.md` 里列出的改动点重新移植。

---

## 一、原作者与授权（必读）

| 项目 | 内容 |
|---|---|
| 原作者 | **Mr-sans-and-InitLoader-s-team** |
| 上游仓库 | https://github.com/Mr-sans-and-InitLoader-s-team/Escape-From-Duckov-Coop-Mod-Preview |
| Steam 创意工坊 | 物品 ID `3591341282`（游戏 AppID `3167020`） |
| 授权 | **GNU AGPLv3 + 附加限制**（见 `LICENSE_RESTRICTIONS.txt`） |

附加限制（AGPLv3 Section 7）里有三条必须遵守：

1. **禁止商业化** —— 不得收费、挂广告、以捐赠为条件提供访问，或打包进营利产品；
2. **禁止运营游戏服务器** —— 不得做成无头中继、托管多人会话的服务端组件；
3. **必须保留显著署名** —— 分发时须带 `NOTICE-ATTRIBUTION.md`，并明确标注这是对原作品的修改。

本仓库的 `README` 顶部、`NOTICE-ATTRIBUTION.md`、以及每个发布包都带有对原作者的署名。

---

## 二、本版本改了什么（相对上游 v1.3.6）

| 改动 | 说明 |
|---|---|
| **取消全员切图投票** | 谁触发切图谁自己走，其他人留在原地图。原投票代码保留但不再可达 |
| **新增场景状态账本** | `SceneStateLedger`：按地图独立记录门、战利品容器、可破坏物、关卡机关与付费状态；后来进入同一张图的玩家看到一致内容 |
| **广播按场景过滤** | 机关 bool、战利品、AI 生成/销毁等只投递给同场景玩家，避免跨图污染 |
| **玩家替身仅同图创建** | 异地图的人物不在本机生成 |
| **移除「仅房主可改」的分图开关** | 判断改为常量。该设置是 host-only 且不参与网络同步，两端读同一个值会出现行为分裂 |
| **本地化补充** | 7 种语言的文案增补 |

- 逐条记录：`CHANGELOG.md`
- 覆盖范围与**已知边界**：`docs/INDEPENDENT_TRAVEL.md`（建议改动前先读）

---

## 三、仓库结构

```
EscapeFromDuckovCoopMod/        Mod 主工程（netstandard2.1）
  Main/SceneService/            场景、切图、状态账本
    SceneNet.cs                 切图流程、场景闸门、独立分图入口
    SceneStateLedger.cs         按场景记账（本版新增）
  Main/NetService.cs            连接、握手、版本门槛
  Main/Loader/Mod.cs            消息分发入口
  Patch/                        Harmony 补丁
EscapeFromDuckovModApi/         提供给其他 Mod 的 API 层（必须与主工程配对）
docs/                           设计与边界文档
Localization/                   7 种语言 JSON
```

---

## 四、如何部署到游戏中

### 4.1 先理解一件事：Mod 不能随便丢进某个文件夹

游戏的 Mod 加载器**只扫描 Steam「已订阅」的创意工坊物品**。它按订阅列表查询 UGC，然后加载对应目录里的 `info.ini` 与 DLL。

**`Duckov_Data\Mods` 不是加载来源** —— 把文件放进去不会生效（这是本项目最容易踩的坑）。修改版必须覆盖到已订阅物品的本地目录：

```
<Steam库>\steamapps\workshop\content\3167020\3591341282\
```

### 4.2 给玩家：用发布包（推荐）

发布包里带 `install.ps1`，不需要装 .NET SDK，也不需要编译。

**前置三步**

1. Steam 创意工坊订阅「逃离鸭科夫联机模组」（物品 ID `3591341282`）
2. **启动一次游戏**，等 Mod 下载完（确认该目录里出现 `info.ini`），然后退出
3. 确认**游戏已完全退出**（Steam 可以开着）

**安装**

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

看到「安装完成，可以启动游戏了。」即可。安装器依次做：

| 步骤 | 说明 |
|---|---|
| 备份 | 原文件复制到 `%LOCALAPPDATA%\DuckovCoopModBackup\<时间戳>\` |
| 覆盖 | 把 `files\` 里的 DLL、`info.ini`、7 个语言文件写入创意工坊 Mod 目录 |
| 同步 Managed | 把 `EscapeFromDuckovModApi.dll` 复制到 `游戏目录\Duckov_Data\Managed\`（**漏这步联机会加载失败**） |
| 校验 | 逐个文件比对 SHA256 |
| 上锁 | 加「只读 + 拒绝写入/删除」，阻止 Steam 自动更新覆盖 |

**常用命令**

| 操作 | 命令 |
|---|---|
| 查看是否装好、是否被 Steam 换回 | `.\install.ps1 -Action Status` |
| 重新安装 / 作者更新后再装一次 | `.\install.ps1` |
| 解锁（允许 Steam 更新） | `.\install.ps1 -Action Unlock` |
| 还原安装前的文件 | `.\install.ps1 -Action Restore` |
| 安装但不上锁 | `.\install.ps1 -NoLock` |

> **所有联机玩家必须使用同一份构建。** 连接时会校验 `BuildInfo.ModVersion`，版本不一致的客机会被直接拒绝，表现为「连不上 / 被踢」。

### 4.3 给开发者：从源码构建

前置条件：

- **游戏本体**（编译需要引用 `Duckov_Data\Managed` 下的游戏程序集，这些文件受版权保护，不随仓库分发）
- **.NET 9 SDK**（解决方案按 VS 17.14 工具链编写，依赖 Polyfill 8.9.0）

```powershell
git clone https://github.com/KingWuzhi/DuckovCoop-IndependentTravel.git
cd DuckovCoop-IndependentTravel
$env:DUCKOV_GAME_DIRECTORY = 'G:\SteamLibrary\steamapps\common\Escape from Duckov'
dotnet build EscapeFromDuckovCoopMod\EscapeFromDuckovCoopMod.csproj -c Release
```

`Directory.Build.props` 会据此推导出 `Duckov_Data\Managed` 的路径。

构建产物会被自动复制到 `Duckov_Data\Mods\联机Mod1\` —— **但这个目录游戏不读**，需要手工搬（见 4.4）。

### 4.4 文件落点（关键）

| 文件 | 必须放到 |
|---|---|
| `EscapeFromDuckovCoopMod.dll` | `...\workshop\content\3167020\3591341282\` |
| `EscapeFromDuckovModApi.dll` | 同一目录 **＋** `Duckov_Data\Managed\`（**两处必须是同一个文件**） |
| `Localization\*.json` | `...\3591341282\Localization\` |
| `info.ini` | `...\3591341282\`（作者的原始文件，本版未修改） |

`Managed` 里那一份是给 Mono 按程序集名解析用的。**两处版本不一致**时，点「继续游戏」会抛 `TypeLoadException: CoopPeer`，表现为**卡在继续界面**——这是本项目历史上最常见的故障，成因就是两个 DLL 被 Steam 换成了不同版本。

### 4.5 为什么要「上锁」

Steam **没有**「对单个创意工坊物品禁用自动更新」的开关。作者一更新，Steam 就会把创意工坊里的 DLL 换回官方版，而 `Managed` 里的 `ModApi` 还是本版的，于是两边错配。

发布包的做法是把这 9 个文件（2 个 DLL + 7 个语言文件）设为「只读 + 拒绝写入/删除」。注意 `Managed\EscapeFromDuckovModApi.dll` **特意没有上锁**——它在游戏本体目录里，锁了可能影响游戏自身的文件校验。

---

## 五、已知限制与排错

| 现象 | 原因 | 处理 |
|---|---|---|
| 卡在「继续游戏」界面 | `Managed` 与创意工坊里的 `ModApi` 版本错配 | 重跑安装器 |
| 客机连不上 / 被踢 | 两端 `BuildInfo.ModVersion` 不一致 | 全员统一用同一份构建 |
| 作者更新后失效 | Steam 覆盖了 DLL | 重跑安装器（已上锁的一般不会发生） |
| 界面显示 v1.4.6，实际是 1.3.6 内核 | `info.ini` 是作者的原始文件，未随本版修改 | 以 DLL 哈希为准，不要看 `info.ini` |
| 分图后另一张图的 AI 不动 | 主机不在那张图，AI 不会在该图模拟 | 设计边界，见 `docs/INDEPENDENT_TRAVEL.md` |
| 客机切图有约 10 秒等待界面 | 场景闸门固定空等（已修复，见 `feat/remove-scene-gate-wait`） | 用该分支的构建 |

---

## 六、当前构建

| 文件 | 大小 | SHA256（前 16 位） |
|---|---|---|
| `EscapeFromDuckovCoopMod.dll` | 2,075,136 B | `E3D4686988F5234A` |
| `EscapeFromDuckovModApi.dll` | 130,560 B | `C1BDE86D83DBF367` |

编译内置版本号：`BuildInfo.ModVersion = "1.3.6.2"`（版本门槛校验的就是这个值，不是 `info.ini`）。