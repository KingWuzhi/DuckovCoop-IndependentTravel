// Escape-From-Duckov-Coop-Mod-Preview
// Copyright (C) 2025  Mr.sans and InitLoader's team
//
// This program is not a free software.
// It's distributed under a license based on AGPL-3.0,
// with strict additional restrictions:
//  YOU MUST NOT use this software for commercial purposes.
//  YOU MUST NOT use this software to run a headless game server.
//  YOU MUST include a conspicuous notice of attribution to
//  Mr-sans-and-InitLoader-s-team/Escape-From-Duckov-Coop-Mod-Preview as the original author.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.

using System;
using System.Collections.Generic;
using Duckov.Scenes;
using LiteNetLib;
using UnityEngine;

namespace EscapeFromDuckovCoopMod;

/// <summary>
/// 场景状态账本（主机侧）。
///
/// 目的：允许玩家各自待在不同地图（独立分图）。主机同一时刻只能加载一个场景，
/// 所以"主机不在的图"只能以数据形式保留状态。本类按 SceneId 记录那些
/// 已经通过环境同步通道传播过的世界状态，玩家进入某个场景时按场景回放，
/// 保证"后来进入同一张图的人看到一致的箱子/门/可破坏物/收费机关"。
///
/// 记录来源：
///   - 等级 bool（门锁、付费机关、载具所需道具等）——变化时记录
///   - 战利品容器开/关状态 —— 快照发送时记录 + 定时巡检记录
///   - 门开/关状态 —— 同上
///   - 可破坏物已死亡 Id —— 同上
///   - 已支付 CostTaker —— 复用 LevelDataBoolNet 里带 SceneId 的静态表
///
/// 注意：账本只覆盖"状态型"内容。主机不在的图里 AI 不模拟、不刷新掉落，
/// 这是当前架构的边界，详见 docs/INDEPENDENT_TRAVEL.md。
/// </summary>
public static class SceneStateLedger
{
    private const int LootChunkSize = 80;
    private const int DoorChunkSize = 80;

    private sealed class SceneRecord
    {
        // keyHash -> (keyString, value)
        public readonly Dictionary<int, KeyValuePair<string, bool>> LevelBools = new();
        public readonly Dictionary<int, bool> LootActive = new();
        public readonly Dictionary<int, bool> DoorsClosed = new();
        public readonly HashSet<uint> DeadDestructibles = new();

        /// <summary>是否真正采集过可破坏物状态；没采集过就不要拿空集合去覆盖客户端。</summary>
        public bool DestructiblesCaptured;
    }

    private static readonly Dictionary<string, SceneRecord> Records =
        new(StringComparer.OrdinalIgnoreCase);

    private static NetService Service => NetService.Instance;
    private static bool IsServer => Service != null && Service.IsServer;
    private static bool NetworkStarted => Service != null && Service.networkStarted;

    /// <summary>当前本地所在场景 Id；取不到时返回空串。</summary>
    public static string CurrentSceneId
    {
        get
        {
            try
            {
                var id = MultiSceneCore.Instance?.SceneInfo?.ID;
                if (!string.IsNullOrEmpty(id)) return id;
            }
            catch
            {
            }

            try
            {
                var sid = SceneNet.Instance != null ? SceneNet.Instance._sceneReadySidSent : null;
                if (!string.IsNullOrEmpty(sid)) return sid;
            }
            catch
            {
            }

            return string.Empty;
        }
    }

    /// <summary>取某个连接当前所在场景；取不到返回空串。</summary>
    public static string ResolvePeerScene(NetPeer peer)
    {
        if (peer == null) return string.Empty;

        if (SceneM._srvPeerScene.TryGetValue(peer, out var sceneId) && !string.IsNullOrEmpty(sceneId))
            return sceneId;

        try
        {
            var service = NetService.Instance;
            if (service != null &&
                service.playerStatuses.TryGetValue(peer, out var status) &&
                status != null &&
                !string.IsNullOrEmpty(status.SceneId))
                return status.SceneId;
        }
        catch
        {
        }

        return string.Empty;
    }

    private static SceneRecord GetRecord(string sceneId)
    {
        if (string.IsNullOrEmpty(sceneId)) return null;

        if (!Records.TryGetValue(sceneId, out var record))
        {
            record = new SceneRecord();
            Records[sceneId] = record;
        }

        return record;
    }

    // ===================== 记录入口 =====================

    public static void RecordLevelBool(string key, bool value)
    {
        if (!IsServer || !NetworkStarted) return;
        if (string.IsNullOrEmpty(key)) return;

        var sceneId = CurrentSceneId;
        var record = GetRecord(sceneId);
        if (record == null) return;

        record.LevelBools[key.GetHashCode()] = new KeyValuePair<string, bool>(key, value);
    }

    public static void RecordLevelBool(string sceneId, string key, bool value)
    {
        if (!IsServer || !NetworkStarted) return;
        if (string.IsNullOrEmpty(key)) return;

        var record = GetRecord(sceneId);
        if (record == null) return;

        record.LevelBools[key.GetHashCode()] = new KeyValuePair<string, bool>(key, value);
    }

    public static void RecordLootState(int key, bool active)
    {
        if (!IsServer || !NetworkStarted) return;
        if (key == 0) return;

        var record = GetRecord(CurrentSceneId);
        if (record == null) return;

        record.LootActive[key] = active;
    }

    public static void RecordDoorState(int key, bool closed)
    {
        if (!IsServer || !NetworkStarted) return;
        if (key == 0) return;

        var record = GetRecord(CurrentSceneId);
        if (record == null) return;

        record.DoorsClosed[key] = closed;
    }

    public static void RecordLoot(int[] keys, bool[] states)
    {
        if (!IsServer || !NetworkStarted) return;
        if (keys == null || states == null) return;

        var record = GetRecord(CurrentSceneId);
        if (record == null) return;

        var count = Math.Min(keys.Length, states.Length);
        for (var i = 0; i < count; i++)
        {
            if (keys[i] == 0) continue;
            record.LootActive[keys[i]] = states[i];
        }
    }

    public static void RecordDoors(int[] keys, bool[] closedStates)
    {
        if (!IsServer || !NetworkStarted) return;
        if (keys == null || closedStates == null) return;

        var record = GetRecord(CurrentSceneId);
        if (record == null) return;

        var count = Math.Min(keys.Length, closedStates.Length);
        for (var i = 0; i < count; i++)
        {
            if (keys[i] == 0) continue;
            record.DoorsClosed[keys[i]] = closedStates[i];
        }
    }

    public static void RecordDestructibles(uint[] deadIds)
    {
        if (!IsServer || !NetworkStarted) return;

        var record = GetRecord(CurrentSceneId);
        if (record == null) return;

        record.DeadDestructibles.Clear();
        if (deadIds == null) return;

        for (var i = 0; i < deadIds.Length; i++)
            record.DeadDestructibles.Add(deadIds[i]);

        record.DestructiblesCaptured = true;
    }

    // ===================== 巡检采集 =====================

    /// <summary>
    /// 抓取主机"当前场景"的环境状态并存进账本。定时调用即可保持账本新鲜，
    /// 这样主机离开该图后，后来进入的玩家仍能拿到最后已知状态。
    /// </summary>
    public static void CaptureCurrentScene()
    {
        if (!IsServer || !NetworkStarted) return;
        if (!LevelManager.LevelInited || LevelManager.Instance == null) return;

        var sceneId = CurrentSceneId;
        if (string.IsNullOrEmpty(sceneId)) return;

        CaptureLoot(sceneId);
        CaptureDoors(sceneId);
        CaptureDestructibles(sceneId);
    }

    private static void CaptureLoot(string sceneId)
    {
        var record = GetRecord(sceneId);
        if (record == null) return;

        try
        {
            foreach (var entry in CoopSyncDatabase.Loot.Entries)
            {
                if (entry == null) continue;

                var key = entry.PositionKey;
                if (key == 0) continue;

                GameObject go = null;
                try
                {
                    if (entry.Loader)
                        go = entry.Loader.gameObject;
                    else if (entry.Lootbox)
                        go = entry.Lootbox.gameObject;
                }
                catch
                {
                    go = null;
                }

                if (go == null) continue;

                var active = false;
                try
                {
                    active = go.activeSelf;
                }
                catch
                {
                }

                record.LootActive[key] = active;
            }
        }
        catch
        {
        }
    }

    private static void CaptureDoors(string sceneId)
    {
        var record = GetRecord(sceneId);
        if (record == null) return;

        try
        {
            var registry = CoopSyncDatabase.Environment.Doors;
            var entries = registry.Entries;
            if (entries == null) return;

            for (var i = 0; i < entries.Count; i++)
            {
                var entry = entries[i];
                if (entry == null) continue;

                var door = entry.Door;
                if (!door) continue;

                registry.Register(door);

                var key = entry.Key;
                if (key == 0)
                    key = Door.TryGetDoorKey(door);

                if (key == 0) continue;

                var closed = true;
                try
                {
                    closed = !door.IsOpen;
                }
                catch
                {
                }

                record.DoorsClosed[key] = closed;
            }
        }
        catch
        {
        }
    }

    private static void CaptureDestructibles(string sceneId)
    {
        var record = GetRecord(sceneId);
        if (record == null) return;

        try
        {
            var destructible = COOPManager.destructible;
            var source = destructible != null ? destructible._deadDestructibleIds : null;
            if (source == null) return;

            record.DeadDestructibles.Clear();
            foreach (var id in source)
                record.DeadDestructibles.Add(id);

            record.DestructiblesCaptured = true;
        }
        catch
        {
        }
    }

    // ===================== 回放 =====================

    /// <summary>
    /// 把指定场景的账本状态发给某个玩家。返回是否真的发送过数据。
    /// 由服务端的快照请求处理与场景就绪处理调用。
    /// </summary>
    public static bool TrySendTo(NetPeer peer, string sceneId)
    {
        if (peer == null) return false;
        if (!IsServer || !NetworkStarted) return false;
        if (string.IsNullOrEmpty(sceneId)) return false;
        if (!Records.TryGetValue(sceneId, out var record)) return false;

        SendLevelBools(peer, record);
        SendCostTakers(peer, sceneId);
        SendLoot(peer, record);
        SendDoors(peer, record);
        SendDestructibles(peer, record);
        return true;
    }

    private static void SendLevelBools(NetPeer peer, SceneRecord record)
    {
        if (record.LevelBools.Count == 0) return;

        foreach (var kv in record.LevelBools)
        {
            var rpc = new EnvLevelDataBoolRpc
            {
                KeyString = kv.Value.Key ?? string.Empty,
                Value = kv.Value.Value,
                KeyHash = kv.Key
            };

            CoopTool.SendRpcTo(peer, in rpc);
        }
    }

    private static void SendCostTakers(NetPeer peer, string sceneId)
    {
        LevelDataBoolNet.Server_SendCostTakerSnapshot(peer, sceneId);
    }

    private static void SendLoot(NetPeer peer, SceneRecord record)
    {
        if (record.LootActive.Count == 0) return;

        var keys = new int[record.LootActive.Count];
        var states = new bool[record.LootActive.Count];
        var index = 0;
        foreach (var kv in record.LootActive)
        {
            keys[index] = kv.Key;
            states[index] = kv.Value;
            index++;
        }

        for (var offset = 0; offset < keys.Length; offset += LootChunkSize)
        {
            var count = Math.Min(LootChunkSize, keys.Length - offset);
            var chunkKeys = new int[count];
            var chunkStates = new bool[count];
            Array.Copy(keys, offset, chunkKeys, 0, count);
            Array.Copy(states, offset, chunkStates, 0, count);

            var rpc = new EnvLootChunkRpc
            {
                Reset = offset == 0,
                Keys = chunkKeys,
                States = chunkStates
            };

            CoopTool.SendRpcTo(peer, in rpc);
        }
    }

    private static void SendDoors(NetPeer peer, SceneRecord record)
    {
        if (record.DoorsClosed.Count == 0) return;

        var keys = new int[record.DoorsClosed.Count];
        var states = new bool[record.DoorsClosed.Count];
        var index = 0;
        foreach (var kv in record.DoorsClosed)
        {
            keys[index] = kv.Key;
            states[index] = kv.Value;
            index++;
        }

        for (var offset = 0; offset < keys.Length; offset += DoorChunkSize)
        {
            var count = Math.Min(DoorChunkSize, keys.Length - offset);
            var chunkKeys = new int[count];
            var chunkStates = new bool[count];
            Array.Copy(keys, offset, chunkKeys, 0, count);
            Array.Copy(states, offset, chunkStates, 0, count);

            var rpc = new EnvDoorChunkRpc
            {
                Reset = offset == 0,
                Keys = chunkKeys,
                ClosedStates = chunkStates
            };

            CoopTool.SendRpcTo(peer, in rpc);
        }
    }

    private static void SendDestructibles(NetPeer peer, SceneRecord record)
    {
        if (!record.DestructiblesCaptured) return;

        var ids = new uint[record.DeadDestructibles.Count];
        var index = 0;
        foreach (var id in record.DeadDestructibles)
            ids[index++] = id;

        var rpc = new EnvDestructibleStateRpc
        {
            Reset = true,
            DeadIds = ids
        };

        CoopTool.SendRpcTo(peer, in rpc);
    }

    /// <summary>新会话开始时清空账本，避免把上一局的地图状态带进新局。</summary>
    public static void Clear()
    {
        Records.Clear();
    }

    public static bool HasScene(string sceneId)
    {
        return !string.IsNullOrEmpty(sceneId) && Records.ContainsKey(sceneId);
    }
}
