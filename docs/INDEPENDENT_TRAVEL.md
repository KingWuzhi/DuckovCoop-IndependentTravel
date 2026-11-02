# 独立分图（Independent Travel）

> 状态：**已全局启用**。v1.3.6.2 起投票全部取消，分图成为唯一行为，不再有开关。
> 改动基于 `master`（v1.3.6，commit `65d13a9`）。
> 第 2 节原先描述的开关已移除，保留作历史记录。

## 1. 需求

原版联机逻辑里，只要有人触发切图（传送机、地图选择、撤离点），就会走「全员投票 → 所有人一起加载同一张图」的流程。本改动让每个人可以自己决定去哪张图：

- 玩家 A 去工厂，玩家 B 留在基地，玩家 C 去农场 —— 互不干涉。
- 后进入同一张图的玩家，看到与先到者一致的地图内容（门、箱子、可破坏物、付费机关）。

## 2. 开关（v1.3.6.2 已移除）

**投票已全部取消，分图是唯一行为。** 设置页的「独立分图」开关已删除，
`SceneNet.IndependentTravelEnabled` 改为返回常量 `true`。

改为常量的原因：该判断在**主机与客户端两侧都会被读到**
（`RPCPlayer` / `AISyncService` / `LevelDataBoolNet` / `Weather`），
而设置项是 host-only（客户端那一栏是灰的、改不动）且不参与网络同步。
读本地值会让两边行为分裂；返回常量后两侧必然一致，也不再依赖 `Config/AISyncSettings.json`。

恢复投票的办法：把 `SceneNet.IndependentTravelEnabled` 改回读取设置值，
并在 `AISyncSettingsUI` 加回开关。投票代码本身**未删除**，只是不再可达
（`Host_BeginSceneVote_Simple` 与 `HandleSceneVoteRequest` 都会走进各自的分图分支）。

以下是原先开关的语义，仅作历史记录：

- `false`：行为与原来完全一致（全员投票 + 一起切图）。
- `true`：切图请求不再广播给所有人，只放行发起者本人。

## 3. 实现要点

### 3.1 切图解耦

所有切图入口原本就收敛在两个方法上，改动只在这两处加分支：

| 角色 | 入口 | 独立分图下的行为 |
| --- | --- | --- |
| 主机 | `SceneNet.Host_BeginSceneVote_Simple` | 直接 `Host_BeginIndependentTravel`：设置目标场景 → `Server_ScheduleSceneLoad(0.35f)` → 只加载主机自己，**不广播** |
| 客户端 | `SceneNet.Client_RequestBeginSceneVote` → `RPCScene.HandleSceneVoteRequest` | 主机收到后走 `Server_BeginClientIndependentTravel`：**只给这个 peer 发 `SceneBeginLoadRpc`**，主机留在原地 |

客户端收到后仍走原有的 `Client_OnBeginSceneLoad` → `AuthorizeLocalSceneLoad` → 本地加载，
因此 `SceneLoaderProxy.LoadScene` 的 Harmony 前缀校验不需要改动。

`SceneNet.Server_HandleSceneReady` 第 4 步原来无条件在主机场景生成该客户端的替身，
现在改为：只有「该客户端与主机同图」才生成，否则销毁主机这边的旧替身。

### 3.2 地图内容一致性：场景账本

主机同一时刻只能加载一个 Unity 场景，所以「主机不在的图」无法实时模拟。
新增 `SceneStateLedger`（`Main/SceneService/SceneStateLedger.cs`）按 `SceneId` 记录世界状态：

| 内容 | 记录来源 | 回放方式 |
| --- | --- | --- |
| 关卡 bool（门锁、机关、载具所需道具） | 每次 `LevelDataBoolNet` 服务端应用/转发时按**发送者所在场景**记账 | 逐条 `EnvLevelDataBoolRpc` |
| 已支付的付费机关 | 复用 `LevelDataBoolNet` 里带 `SceneId` 的 `PaidCostTakerStates` | `Server_SendCostTakerSnapshot(peer, sceneId)` |
| 战利品容器开/关 | 快照发送时逐个记录 + 主机每 5 秒巡检 `CoopSyncDatabase.Loot` | 分块 `EnvLootChunkRpc`（80/块） |
| 门开/关 | 同上（`CoopSyncDatabase.Environment.Doors`） | 分块 `EnvDoorChunkRpc`（80/块） |
| 可破坏物已摧毁 | 快照发送时 + 定时巡检 `_deadDestructibleIds` | `EnvDestructibleStateRpc` |

回放触发点：

1. `Weather.Server_HandleSnapshotRequest` —— 请求者 `SceneId` 与主机不同时，
   **不再**用主机现场快照回复，改用 `SceneStateLedger.TrySendTo(peer, peerScene)`，
   只补发时钟与天气（这两者是全局状态）。
2. `SceneStateLedger.CaptureCurrentScene()` 在 `Weather.Server_Update` 里每 5 秒跑一次，
   保证主机离开某图前，账本里已有该图的最新状态。

### 3.3 防止跨图污染

开启独立分图后，下列广播改为「只发给同场景的连接」：

- `CoopTool.SendRpcToScene`（新增）：按 `_srvPeerScene` / `playerStatuses.SceneId` 过滤，
  场景未知的连接一律不发（等它上报 `SCENE_READY` 后用账本补）。
- `LevelDataBoolNet` 的机关 bool 与付费广播。
- `Weather` 的战利品定时广播（`SendLootSnapshotToSameScene`）。
- `AISyncService` 的 AI 生成/销毁广播，以及 AI 快照请求（不同图直接忽略）。

玩家替身也做了双向按场景过滤：

- **客户端**：`HandlePlayerStatusUpdate` 只为同图玩家创建/更新替身；
  当某个玩家切到别的图后，本地残留的替身会被自动销毁。
- **主机**：`HandleClientStatusUpdate` 同样只为同图客户端创建/更新替身，
  不同图时销毁主机这边的旧克隆。

（v1.3.6.2 起分图恒为开启，上述过滤条件不再有“短路”路径。）

## 4. 已知边界（重要）

1. **离开主机所在图的区域不模拟**：AI 不会移动/攻击，掉落不会新增。
   该图对进入者而言是「静态的、状态一致的世界」。
2. **两名玩家都在主机不在的图时，他们之间只同步轻量状态**：
   关卡 bool、付费机关能同步；门的开关依赖主机本地找到同 key 的门对象，因此
   在主机不在的图里**不会**互相同步；战利品拾取、AI 互相同步同样不成立。
3. **账本按会话存活**：重开房或重连会 `Clear()`；主机从未去过的图没有账本，
   首个进入者看到的是全新地图。
4. **撤离/结算按「本图存活玩家」判定**（`SceneM.AllPlayersDead` 已按同图过滤），
   跨图组队撤离的结算语义与原版不同，需要实机确认。
5. `ExitSyncService` 只接受与主机同场景的出口快照请求，异地图的出口状态不会回放。

要彻底解决 1、2、5，需要引入「场景权威所有者」（第一个进入该图的玩家代理 AI/战利品模拟并上报主机），
属于后续架构级工作，不在本次改动范围内。

## 5. 改动文件索引

| 文件 | 说明 |
| --- | --- |
| `Main/SceneService/SceneStateLedger.cs` | 新增：按场景记账 + 回放 |
| `Main/SceneService/SceneNet.cs` | 切图分流、主机/客户端独立切图、替身按图清理 |
| `Net/Rpc/Handler/RPCScene.cs` | 切图请求分流 |
| `Main/CoopAISettings.cs` | ~~`IndependentTravel` 设置项~~（v1.3.6.2 已移除） |
| `Main/UI/AISyncSettingsUI.cs` | ~~设置界面开关~~（v1.3.6.2 已移除，分图恒开） |
| `Main/Localization/LocalizationManager.cs`、`Localization/{zh-CN,en-US}.json` | 文案 |
| `Main/WeatherAndTime/Weather.cs` | 快照按场景路由、定时巡检、战利品广播按场景 |
| `Main/SceneService/LevelDataBoolNet.cs` | bool 按发送者场景记账、付费快照按场景、广播按场景 |
| `Main/CoopTool.cs` | `SendRpcToScene` |
| `Main/SceneService/AISyncService.cs` | AI 快照/广播按场景过滤 |
| `Net/Rpc/Handler/RPCPlayer.cs` | 玩家替身按场景创建 |
| `Main/NetService.cs` | 新会话清空账本与场景表 |

## 6. 构建

与上游一致：设置 `DUCKOV_GAME_DIRECTORY`（游戏根目录）→ 打开 `EscapeFromDuckovCoopMod.sln` → Release 生成。
本次改动未新增 NuGet/程序集依赖，仅使用仓库内已有的 `LiteNetLib`、`Newtonsoft.Json` 与游戏程序集。

### 已验证的编译结果

本改动已实际编译通过（Release、netstandard2.1）：

```text
.NET SDK 9.0.319
EscapeFromDuckovCoopMod.dll   2,075,648 字节
EscapeFromDuckovModApi.dll      130,560 字节
0 error（52 个 warning 全部为改动前就存在的既有告警）
```

要求与注意事项：

1. **需要 .NET SDK 9 或更高版本**（VS 2022 17.12+ / 17.14 对应 SDK 9）。
   `Polyfill 8.9.0` 的 `contentFiles` 使用了 C# 13 的 `ref struct` 接口，
   用 SDK 8 编译会报 `CS8652: 功能"ref 结构接口"当前为预览版`。
2. `DUCKOV_GAME_DIRECTORY` 必须指向游戏根目录（不是 `Duckov_Data`、不是 `Managed`）。
   `Directory.Build.props` 会据此推导出 `DUCKOV_GAME_MANAGED` 与 `DUCKOV_MODS_DIRECTORY`。
3. 若命令行还原失败，可逐项目还原（解决方案级 restore 在某些环境下会静默失败且不报错）：

   ```powershell
   dotnet restore EscapeFromDuckovModApi\EscapeFromDuckovModApi.csproj
   dotnet restore EscapeFromDuckovCoopMod\EscapeFromDuckovCoopMod.csproj
   dotnet build EscapeFromDuckovCoopMod\EscapeFromDuckovCoopMod.csproj -c Release --no-restore
   ```

4. 若 `api.nuget.org` 不可达（报 `NU1301`），可预先下载 `Polyfill` 8.9.0 的 `.nupkg`
   放进本地文件夹，再用 `--source <文件夹>` 还原。
5. 生成后 `CopyToModsFolder` 会把 DLL 与本地化文件复制到
   `Duckov_Data\Mods\联机Mod1\`。只想验证编译、不想动游戏目录时，可覆盖该路径：

   ```powershell
   dotnet build ... -p:DUCKOV_MODS_DIRECTORY=<自定义暂存目录>
   ```

## 7. 安装到游戏（实测结论：不是 `Duckov_Data\Mods`）

**结论：游戏不会从这个仓库工程输出的 `Duckov_Data\Mods\联机Mod1\` 加载联机 Mod。**

实测依据：

- 游戏内置 Mod 管理器位于 `Duckov_Data\Managed\TeamSoda.Duckov.Core.dll`（含 `info.ini` / `publishedFileId` / `ModManager` / `Loading mod dll at path:` / `.ModBehaviour` 等字符串）。其机制是：扫描含 `info.ini` 的 Mod 目录 → 用 `info.ini` 的 `name` 作为标识 → 加载同名 DLL → 实例化 `<name>.ModBehaviour`。本仓库 `EscapeFromDuckovCoopMod/Main/Loader/Loader.cs` 中的 `namespace EscapeFromDuckovCoopMod; class ModBehaviour : Duckov.Modding.ModBehaviour` 就是这个入口。
- 联机 Mod 实际安装在 Steam 创意工坊目录（游戏 appid `3167020`）：

  ```
  <SteamLibrary>\steamapps\workshop\content\3167020\3591341282\
      info.ini                     ← name = EscapeFromDuckovCoopMod
      EscapeFromDuckovCoopMod.dll  ← 游戏真正加载的文件
      EscapeFromDuckovModApi.dll
      Localization\  Assets\  preview.png
  ```

- 游戏侧 Mod 列表（`%USERPROFILE%\AppData\LocalLow\TeamSoda\Duckov\Player.log` 的 `Sorted mods` 段）与 `Saves\Mods.ES3` 中的 `priority_<name>` 键，全部来自各 Mod 的 `info.ini` 的 `name`。
- 本仓库工程的 `CopyToModsFolder` 目标只复制 DLL 与 `Localization\`，**不生成 `info.ini`**，所以该输出目录不被游戏识别。

### 让改动生效的正确做法

用编译产物覆盖创意工坊目录中的主 DLL，并同步本次改动的本地化文件：

```
<workshop>\3591341282\EscapeFromDuckovCoopMod.dll        ← 用本工程 bin\Release 输出覆盖
<workshop>\3591341282\EscapeFromDuckovModApi.dll         ← 与主 DLL 同一批编译，需保持一致
<workshop>\3591341282\Localization\{zh-CN,en-US}.json    ← 本次新增键所在的文件
```

注意：

- Steam 在上游更新该创意工坊项目、或执行"验证游戏文件完整性"时会**覆盖回原版**，覆盖前务必留存备份与哈希记录。
- 只放 DLL 还不够：游戏内需先接受 Mod 协议，再在模组管理界面**启用**该 Mod。日志里 `ModActive_EscapeFromDuckovCoopMod: False` 即表示未启用（默认所有 Mod 都是关闭的）。
- `BepInEx\plugins\DuckovCoop.dll`（v0.1.0，约 30KB）是独立的 BepInEx 插件，与本模组的原生 Mod 入口无关，不要与上表中的 DLL 混淆。

## 8. 建议的实机验证清单

1. 只开房、不进图：设置能保存并在重进时保持。
2. 主机 A 图、客户端 B 图：双方互不可见，AI 不在对方图里出现。
3. 客户端进图 → 打掉一个门锁/开一个箱子 → 返回基地 → 再进同一张图：状态保持。
4. 主机进图 → 开门/开箱 → 主机离开 → 客户端进入同一张图：看到主机改过的状态。
5. 两名客户端先进同一张图（主机不在）：确认门/箱子互相同步的边界符合第 4 节描述。
6. 切图不再需要投票：任一方随时切图，另一方留在原地不受影响。
7. 撤离、死亡观战等原流程确认无回归。