using System;
using System.Collections.Generic;
using System.Linq;
using common;
using common.resources;
using Newtonsoft.Json;
using StackExchange.Redis;
using wServer.realm.entities;

namespace wServer.realm
{
    // V1 deliberately stores only a deterministic imprint key in the existing
    // per-item metadata record.  Item packets remain ushort object types.
    public sealed class EclipseImprintDefinition
    {
        public string Id;
        public string DisplayName;
        public int ShardCost;
        public Dictionary<StatsType, int> Effects;
    }

    public static class EclipseImprintService
    {
        private const string MetadataKey = "imprint";
        private const int OperationLedgerLimit = 128;

        private static readonly HashSet<ushort> EligibleTypes = new HashSet<ushort>
        {
            0xF91F, // Eye of the Ominous
            0xF920, // Mantle of the Below
            0xF921, // Judgement
            0xF938, // Nacre Talisman
            0xF947, // Sunforged Plate
            0xF956, // Parallax Bulwark
            0xF96B, // Crownrender
            0xF96C, // Eclipse Aegis
            0xF96D, // Zenithal Ring
            0xF970  // Lightless Staff
        };

        private static readonly Dictionary<string, EclipseImprintDefinition> Definitions =
            new Dictionary<string, EclipseImprintDefinition>(StringComparer.OrdinalIgnoreCase)
            {
                { "swift", new EclipseImprintDefinition { Id = "swift", DisplayName = "Swift", ShardCost = 25,
                    Effects = new Dictionary<StatsType, int> { { StatsType.Speed, 3 }, { StatsType.MaximumHP, -25 } } } },
                { "bulwark", new EclipseImprintDefinition { Id = "bulwark", DisplayName = "Bulwark", ShardCost = 25,
                    Effects = new Dictionary<StatsType, int> { { StatsType.Defense, 4 }, { StatsType.Dexterity, -2 } } } },
                { "focused", new EclipseImprintDefinition { Id = "focused", DisplayName = "Focused", ShardCost = 25,
                    Effects = new Dictionary<StatsType, int> { { StatsType.Wisdom, 3 }, { StatsType.MaximumHP, -20 } } } },
                { "hunter", new EclipseImprintDefinition { Id = "hunter", DisplayName = "Hunter", ShardCost = 25,
                    Effects = new Dictionary<StatsType, int> { { StatsType.Attack, 2 }, { StatsType.Dexterity, 2 }, { StatsType.Vitality, -2 } } } }
            };

        public static string Describe()
        {
            return "[Imprints] " + string.Join(" | ", Definitions.Values.Select(d => d.DisplayName + " (" + d.ShardCost + " imprint_shard): " + DescribeEffects(d)).ToArray());
        }

        public static IEnumerable<EclipseServiceUiEntry> BuildUi(Player player)
        {
            if (player == null || player.Client.Account == null || player.DbLink == null)
                return Enumerable.Empty<EclipseServiceUiEntry>();

            var result = new List<EclipseServiceUiEntry>();
            var owned = MaterialVaultService.GetBalance(player.Client.Account, "imprint_shard");
            for (var slot = 4; slot < player.Inventory.Length; slot++)
            {
                common.resources.Item item;
                RInventory.ItemInstanceRecord record;
                if (ValidateBagItem(player, slot, out item, out record) != null)
                    continue;
                var current = GetImprint(record.Metadata);
                if (!string.IsNullOrEmpty(current))
                {
                    result.Add(new EclipseServiceUiEntry
                    {
                        ServiceKind = "imprint",
                        Title = "Bag " + slot + ": " + item.ObjectId,
                        Details = "Current Imprint: " + FormatImprint(current),
                        Command = "",
                        ActionLabel = "Applied",
                        Craftable = false
                    });
                    continue;
                }

                foreach (var definition in Definitions.Values.OrderBy(value => value.Id))
                    result.Add(new EclipseServiceUiEntry
                    {
                        ServiceKind = "imprint",
                        Title = "Bag " + slot + ": " + item.ObjectId + " — " + definition.DisplayName,
                        Details = DescribeEffects(definition) + " | Cost " + definition.ShardCost + " imprint_shard (owned " + owned + ")",
                        Command = "/imprint apply " + slot + " " + definition.Id,
                        ActionLabel = "Apply",
                        Craftable = owned >= definition.ShardCost
                    });
            }
            return result;
        }

        public static string Inspect(Player player, int slot)
        {
            common.resources.Item item;
            RInventory.ItemInstanceRecord record;
            var error = ValidateBagItem(player, slot, out item, out record);
            if (error != null) return error;
            var imprint = GetImprint(record.Metadata);
            return string.IsNullOrEmpty(imprint)
                ? "[Imprint] " + item.ObjectId + " is eligible and has no Imprint."
                : "[Imprint] " + item.ObjectId + " has " + FormatImprint(imprint) + ".";
        }

        public static string Preview(Player player, int slot, string imprintId)
        {
            common.resources.Item item;
            RInventory.ItemInstanceRecord record;
            var error = ValidateBagItem(player, slot, out item, out record);
            if (error != null) return error;
            EclipseImprintDefinition definition;
            if (!Definitions.TryGetValue((imprintId ?? "").Trim(), out definition)) return "Unknown Imprint. Use /imprint for available Imprints.";
            if (!string.IsNullOrEmpty(GetImprint(record.Metadata))) return "This item already has an Imprint.";
            return "[Imprint Preview] " + item.ObjectId + " -> " + definition.DisplayName + ": " + DescribeEffects(definition) + ". Cost: " + definition.ShardCost + " imprint_shard.";
        }

        public static string Apply(Player player, int slot, string imprintId)
        {
            common.resources.Item item;
            RInventory.ItemInstanceRecord record;
            var error = ValidateBagItem(player, slot, out item, out record);
            if (error != null) return error;
            EclipseImprintDefinition definition;
            if (!Definitions.TryGetValue((imprintId ?? "").Trim(), out definition)) return "Unknown Imprint. Use /imprint for available Imprints.";
            if (!string.IsNullOrEmpty(GetImprint(record.Metadata))) return "This item already has an Imprint.";

            var account = player.Client.Account;
            var operation = "imprint:" + account.AccountId + ":" + record.Id;
            lock (account)
            {
                // Reload both sides before CAS so a retry or slot mutation can
                // never spend shards against a stale item record.
                account.Reload("materialVaultState");
                player.DbLink.Reload(player.DbLink.Field + ".instances");
                var records = player.DbLink.ItemInstances;
                if (slot >= records.Length || records[slot] == null || records[slot].Id != record.Id ||
                    records[slot].ObjectType != item.ObjectType || player.Inventory[slot] != item)
                    return "Inventory changed; no shards were spent.";
                if (!string.IsNullOrEmpty(GetImprint(records[slot].Metadata))) return "This item already has an Imprint.";

                MaterialVaultState materialState;
                try { materialState = JsonConvert.DeserializeObject<MaterialVaultState>(account.MaterialVaultState) ?? new MaterialVaultState(); }
                catch { materialState = new MaterialVaultState(); }
                if (materialState.Balances == null) materialState.Balances = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                if (materialState.AppliedOperations == null) materialState.AppliedOperations = new Dictionary<string, int>();
                int existing;
                if (materialState.AppliedOperations.TryGetValue(operation, out existing)) return "This Imprint request was already processed.";
                int balance;
                materialState.Balances.TryGetValue("imprint_shard", out balance);
                if (balance < definition.ShardCost) return "Insufficient imprint_shard (need " + definition.ShardCost + ", have " + Math.Max(0, balance) + ").";

                var nextRecords = records.Select(r => r == null ? null : new RInventory.ItemInstanceRecord { Id = r.Id, ObjectType = r.ObjectType, Metadata = r.Metadata ?? "" }).ToArray();
                nextRecords[slot].Metadata = SetImprint(nextRecords[slot].Metadata, definition.Id);
                materialState.Balances["imprint_shard"] = balance - definition.ShardCost;
                Remember(materialState, operation, balance - definition.ShardCost);

                var database = account.Database;
                var oldMaterial = database.HashGet(account.Key, "materialVaultState");
                var oldRecords = database.HashGet(player.DbLink.Key, player.DbLink.Field + ".instances");
                var tx = database.CreateTransaction();
                tx.AddCondition(Condition.HashEqual(account.Key, "materialVaultState", oldMaterial));
                tx.AddCondition(Condition.HashEqual(player.DbLink.Key, player.DbLink.Field + ".instances", oldRecords));
                tx.HashSetAsync(account.Key, "materialVaultState", JsonConvert.SerializeObject(materialState));
                tx.HashSetAsync(player.DbLink.Key, player.DbLink.Field + ".instances", JsonConvert.SerializeObject(nextRecords));
                if (!tx.Execute()) return "Imprint could not be committed; no shards were spent.";

                account.Reload("materialVaultState");
                player.DbLink.Reload(player.DbLink.Field + ".instances");
                return "Applied " + definition.DisplayName + " to " + item.ObjectId + ". Spent " + definition.ShardCost + " imprint_shard.";
            }
        }

        // Called only by the equipment boost calculation. Base XML stats stay
        // untouched; an un-imprinted object type therefore remains identical.
        internal static IEnumerable<KeyValuePair<StatsType, int>> EffectsFor(Player player, int slot, common.resources.Item item)
        {
            if (player == null || player.DbLink == null || item == null || slot < 0 || slot >= 4) return Enumerable.Empty<KeyValuePair<StatsType, int>>();
            var records = player.DbLink.ItemInstances;
            if (slot >= records.Length || records[slot] == null || records[slot].ObjectType != item.ObjectType) return Enumerable.Empty<KeyValuePair<StatsType, int>>();
            var imprint = GetImprint(records[slot].Metadata);
            if (string.IsNullOrEmpty(imprint)) return Enumerable.Empty<KeyValuePair<StatsType, int>>();
            EclipseImprintDefinition definition;
            return Definitions.TryGetValue(imprint, out definition) ? definition.Effects : Enumerable.Empty<KeyValuePair<StatsType, int>>();
        }

        private static string ValidateBagItem(Player player, int slot, out common.resources.Item item, out RInventory.ItemInstanceRecord record)
        {
            item = null; record = null;
            if (player == null || player.DbLink == null) return "Character item identity is unavailable.";
            if (slot < 4 || slot >= player.Inventory.Length) return "Only unequipped bag slots may be Imprinted.";
            item = player.Inventory[slot];
            if (item == null) return "That slot is empty.";
            if (!EligibleTypes.Contains(item.ObjectType)) return item.ObjectId + " is not eligible for Eclipse Imprints.";
            var records = player.DbLink.ItemInstances;
            if (slot >= records.Length || records[slot] == null || records[slot].ObjectType != item.ObjectType || string.IsNullOrWhiteSpace(records[slot].Id)) return "Item identity is invalid; no shards were spent.";
            record = records[slot];
            return null;
        }

        private static string GetImprint(string metadata)
        {
            if (string.IsNullOrWhiteSpace(metadata)) return null;
            foreach (var entry in metadata.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var pair = entry.Split(new[] { '=' }, 2);
                if (pair.Length == 2 && pair[0].Trim().Equals(MetadataKey, StringComparison.OrdinalIgnoreCase)) return pair[1].Trim().ToLowerInvariant();
            }
            return null;
        }

        private static string SetImprint(string metadata, string imprint)
        {
            var values = (metadata ?? "").Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(entry => !entry.Split(new[] { '=' }, 2)[0].Trim().Equals(MetadataKey, StringComparison.OrdinalIgnoreCase)).ToList();
            values.Add(MetadataKey + "=" + imprint.ToLowerInvariant());
            return string.Join(";", values.ToArray());
        }

        private static void Remember(MaterialVaultState state, string operation, int balance)
        {
            if (state.AppliedOperations.Count >= OperationLedgerLimit)
                state.AppliedOperations.Remove(state.AppliedOperations.Keys.OrderBy(x => x, StringComparer.Ordinal).First());
            state.AppliedOperations[operation] = balance;
        }

        private static string FormatImprint(string imprint)
        {
            EclipseImprintDefinition definition;
            return Definitions.TryGetValue(imprint ?? "", out definition) ? definition.DisplayName + " (" + DescribeEffects(definition) + ")" : imprint;
        }

        private static string DescribeEffects(EclipseImprintDefinition definition)
        {
            return string.Join(", ", definition.Effects.Select(effect => (effect.Value >= 0 ? "+" : "") + effect.Value + " " + effect.Key).ToArray());
        }
    }
}
