using System;
using System.Collections.Generic;
using System.Linq;
using common;
using common.resources;
using Newtonsoft.Json;
using wServer.realm.entities;

namespace wServer.realm
{
    public sealed class ForgeRecipe
    {
        public string Id;
        public ushort OutputType;
        public Dictionary<string, int> Costs;
    }

    public sealed class ForgeState { public long LastOperationUtcTicks; }

    public static class ForgeV1Service
    {
        private const int OperationCooldownSeconds = 2;
        private static readonly Dictionary<ushort, int> SalvageValues = new Dictionary<ushort, int>
        {
            { 0xF91F, 60 }, { 0xF920, 80 }, { 0xF921, 120 }
        };
        private static readonly Dictionary<string, ForgeRecipe> Recipes = new Dictionary<string, ForgeRecipe>(StringComparer.OrdinalIgnoreCase)
        {
            { "eye_of_ominous", new ForgeRecipe { Id = "eye_of_ominous", OutputType = 0xF91F, Costs = new Dictionary<string, int> { { "echo_dust", 60 }, { "eye_blueprint", 1 } } } },
            { "mantle_of_below", new ForgeRecipe { Id = "mantle_of_below", OutputType = 0xF920, Costs = new Dictionary<string, int> { { "echo_dust", 80 }, { "mantle_blueprint", 1 } } } },
            { "judgement", new ForgeRecipe { Id = "judgement", OutputType = 0xF921, Costs = new Dictionary<string, int> { { "echo_dust", 120 }, { "judgement_blueprint", 1 } } } }
        };

        public static string Describe(string recipe)
        {
            ForgeRecipe value;
            if (!string.IsNullOrWhiteSpace(recipe) && Recipes.TryGetValue(recipe.Trim(), out value))
                return "[Forge] " + value.Id + " -> 0x" + value.OutputType.ToString("x4") + " | " + string.Join(", ", value.Costs.Select(c => c.Value + " " + c.Key).ToArray());
            return "[Forge] Recipes: " + string.Join(", ", Recipes.Keys.ToArray()) + ". Use /forge preview <recipe>, /forge salvage <bag-slot>, or /forge craft <recipe>.";
        }

        public static string Salvage(Player player, int slot)
        {
            if (player == null || slot < 4 || slot >= player.Inventory.Length)
                return "Only unequipped bag slots may be salvaged.";
            var item = player.Inventory[slot];
            if (item == null) return "That slot is empty.";
            int dust;
            if (!SalvageValues.TryGetValue(item.ObjectType, out dust)) return "That item is not eligible for Echo Dust salvage.";
            var account = player.Client.Account;
            lock (account)
            {
                string operation;
                if (!TryBegin(account, "salvage", out operation)) return "Forge request already processed; wait before retrying.";
                // Check the exact item again while holding the account mutation lock.
                if (player.Inventory[slot] != item) return "Inventory changed; nothing was salvaged.";
                var deposit = MaterialVaultService.TryDeposit(account, "echo_dust", dust, operation);
                if (!deposit.Success) return deposit.Error;
                player.Inventory[slot] = null;
                return "Salvaged " + item.ObjectId + " into " + dust + " Echo Dust.";
            }
        }

        public static string Craft(Player player, string recipeId)
        {
            ForgeRecipe recipe;
            if (player == null || !Recipes.TryGetValue(recipeId ?? "", out recipe)) return "Unknown Forge recipe.";
            Item output;
            if (!player.Manager.Resources.GameData.Items.TryGetValue(recipe.OutputType, out output)) return "Forge output is not registered.";
            var outputSlot = player.Inventory.GetAvailableInventorySlot(output);
            if (outputSlot < 4) return "You need an empty bag slot before crafting.";
            var account = player.Client.Account;
            lock (account)
            {
                string operation;
                if (!TryBegin(account, "craft:" + recipe.Id, out operation)) return "Forge request already processed; wait before retrying.";
                foreach (var cost in recipe.Costs)
                    if (MaterialVaultService.GetBalance(account, cost.Key) < cost.Value)
                        return "Insufficient " + cost.Key + ".";

                var spent = new List<KeyValuePair<string, int>>();
                foreach (var cost in recipe.Costs)
                {
                    var result = MaterialVaultService.TrySpend(account, cost.Key, cost.Value, operation + ":" + cost.Key);
                    if (!result.Success)
                    {
                        foreach (var refund in spent)
                            MaterialVaultService.TryDeposit(account, refund.Key, refund.Value, operation + ":refund:" + refund.Key);
                        return "Forge failed before output creation; materials were restored.";
                    }
                    spent.Add(cost);
                }
                if (player.Inventory[outputSlot] != null)
                {
                    foreach (var refund in spent)
                        MaterialVaultService.TryDeposit(account, refund.Key, refund.Value, operation + ":refund:" + refund.Key);
                    return "Forge output slot changed; materials were restored.";
                }
                player.Inventory[outputSlot] = output;
                return "Forged " + output.ObjectId + ".";
            }
        }

        public static bool ValidateResources(IDictionary<ushort, Item> items, out string error)
        {
            foreach (var recipe in Recipes.Values)
            {
                if (!items.ContainsKey(recipe.OutputType)) { error = "Missing Forge output 0x" + recipe.OutputType.ToString("x4"); return false; }
                foreach (var cost in recipe.Costs)
                    if (!MaterialVaultService.IsKnownMaterial(cost.Key)) { error = "Unknown Forge material " + cost.Key; return false; }
            }
            error = null;
            return true;
        }

        private static bool TryBegin(DbAccount account, string action, out string operation)
        {
            var state = Load(account);
            var now = DateTime.UtcNow;
            operation = "forge:" + account.AccountId + ":" + action + ":" + now.Ticks;
            if (state.LastOperationUtcTicks > 0 && now - new DateTime(state.LastOperationUtcTicks, DateTimeKind.Utc) < TimeSpan.FromSeconds(OperationCooldownSeconds)) return false;
            state.LastOperationUtcTicks = now.Ticks;
            Save(account, state);
            return true;
        }
        private static ForgeState Load(DbAccount account) { try { return JsonConvert.DeserializeObject<ForgeState>(account.ForgeState) ?? new ForgeState(); } catch { return new ForgeState(); } }
        private static void Save(DbAccount account, ForgeState state) { account.ForgeState = JsonConvert.SerializeObject(state); account.FlushAsync().Wait(); }
    }
}
