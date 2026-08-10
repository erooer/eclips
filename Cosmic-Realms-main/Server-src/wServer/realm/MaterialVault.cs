using System;
using System.Collections.Generic;
using System.Linq;
using common;
using Newtonsoft.Json;

namespace wServer.realm
{
    public sealed class MaterialDefinition
    {
        public string Id;
        public string DisplayName;
        public bool AutoDeposit;
    }

    public sealed class MaterialVaultState
    {
        public Dictionary<string, int> Balances = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        // Bounded operation ledger makes caller retries safe without allowing the
        // account JSON to grow indefinitely.
        public Dictionary<string, int> AppliedOperations = new Dictionary<string, int>();
    }

    public sealed class MaterialOperationResult
    {
        public bool Success;
        public bool Duplicate;
        public int Balance;
        public string Error;
    }

    // Account-wide material ledger. It deliberately accepts only stable internal
    // material IDs; inventory items, marks, potions, gear, chests and consumables
    // have no route into this service.
    public static class MaterialVaultService
    {
        public const int DefaultCap = 9999;
        private const int OperationLedgerLimit = 128;

        private static readonly Dictionary<string, MaterialDefinition> Definitions =
            new Dictionary<string, MaterialDefinition>(StringComparer.OrdinalIgnoreCase)
            {
                { "echo_dust", new MaterialDefinition { Id = "echo_dust", DisplayName = "Echo Dust", AutoDeposit = true } },
                { "sigil_fragment", new MaterialDefinition { Id = "sigil_fragment", DisplayName = "Sigil Fragment", AutoDeposit = true } },
                { "threat_fragment", new MaterialDefinition { Id = "threat_fragment", DisplayName = "Threat Fragment", AutoDeposit = true } },
                { "citadel_fragment", new MaterialDefinition { Id = "citadel_fragment", DisplayName = "Citadel Fragment", AutoDeposit = true } },
                { "imprint_shard", new MaterialDefinition { Id = "imprint_shard", DisplayName = "Imprint Shard", AutoDeposit = true } },
                { "event_token", new MaterialDefinition { Id = "event_token", DisplayName = "Event Token", AutoDeposit = true } }
            };

        public static IEnumerable<MaterialDefinition> All { get { return Definitions.Values.OrderBy(m => m.Id); } }

        public static int GetBalance(DbAccount account, string materialId)
        {
            if (account == null || !Definitions.ContainsKey(materialId ?? "")) return 0;
            lock (account) return GetBalance(Load(account), materialId);
        }

        public static MaterialOperationResult TryDeposit(DbAccount account, string materialId, int amount, string operationId)
        {
            return Apply(account, materialId, amount, operationId, true, false);
        }

        public static MaterialOperationResult TryAutoDeposit(DbAccount account, string materialId, int amount, string operationId)
        {
            MaterialDefinition material;
            if (!Definitions.TryGetValue(materialId ?? "", out material) || !material.AutoDeposit)
                return Fail("Material is not configured for auto-deposit.");
            return Apply(account, materialId, amount, operationId, true, false);
        }

        // Withdraw and Spend are intentionally separate names for later UI and
        // direct-consumption callers, but share the same atomic debit path.
        public static MaterialOperationResult TryWithdraw(DbAccount account, string materialId, int amount, string operationId)
        {
            return Apply(account, materialId, amount, operationId, false, false);
        }

        public static MaterialOperationResult TrySpend(DbAccount account, string materialId, int amount, string operationId)
        {
            return Apply(account, materialId, amount, operationId, false, true);
        }

        public static string Describe(DbAccount account, string requestedMaterial)
        {
            if (!string.IsNullOrWhiteSpace(requestedMaterial))
            {
                MaterialDefinition material;
                if (!Definitions.TryGetValue(requestedMaterial.Trim(), out material))
                    return "Unknown material. Valid IDs: " + string.Join(", ", All.Select(m => m.Id).ToArray());
                return string.Format("[Materials] {0} ({1}): {2}/{3}", material.DisplayName, material.Id, GetBalance(account, material.Id), DefaultCap);
            }
            return "[Materials] " + string.Join(" | ", All.Select(m => m.DisplayName + ": " + GetBalance(account, m.Id) + "/" + DefaultCap).ToArray());
        }

        private static MaterialOperationResult Apply(DbAccount account, string materialId, int amount, string operationId, bool credit, bool spend)
        {
            MaterialDefinition material;
            if (account == null) return Fail("Account is unavailable.");
            if (!Definitions.TryGetValue(materialId ?? "", out material)) return Fail("Invalid material ID.");
            if (amount <= 0) return Fail("Amount must be positive.");
            if (string.IsNullOrWhiteSpace(operationId)) return Fail("A unique operation ID is required.");

            lock (account)
            {
                var state = Load(account);
                int priorBalance;
                if (state.AppliedOperations.TryGetValue(operationId, out priorBalance))
                    return new MaterialOperationResult { Success = true, Duplicate = true, Balance = priorBalance };

                var balance = GetBalance(state, material.Id);
                if (credit)
                {
                    if (amount > DefaultCap - balance) return Fail("Material Vault cap reached.", balance);
                    balance += amount;
                }
                else
                {
                    if (amount > balance) return Fail(spend ? "Insufficient material balance for spend." : "Insufficient material balance for withdrawal.", balance);
                    balance -= amount;
                }
                state.Balances[material.Id] = balance;
                Remember(state, operationId, balance);
                Save(account, state);
                return new MaterialOperationResult { Success = true, Balance = balance };
            }
        }

        private static void Remember(MaterialVaultState state, string operationId, int balance)
        {
            if (state.AppliedOperations.Count >= OperationLedgerLimit)
                state.AppliedOperations.Remove(state.AppliedOperations.Keys.OrderBy(k => k, StringComparer.Ordinal).First());
            state.AppliedOperations[operationId] = balance;
        }

        private static int GetBalance(MaterialVaultState state, string materialId)
        {
            int balance;
            return state.Balances.TryGetValue(materialId, out balance) ? Math.Max(0, Math.Min(DefaultCap, balance)) : 0;
        }

        private static MaterialVaultState Load(DbAccount account)
        {
            try { return JsonConvert.DeserializeObject<MaterialVaultState>(account.MaterialVaultState) ?? new MaterialVaultState(); }
            catch { return new MaterialVaultState(); }
        }

        private static void Save(DbAccount account, MaterialVaultState state)
        {
            account.MaterialVaultState = JsonConvert.SerializeObject(state);
            account.FlushAsync().Wait();
        }

        private static MaterialOperationResult Fail(string error, int balance = 0)
        {
            return new MaterialOperationResult { Success = false, Balance = balance, Error = error };
        }
    }
}
