using System;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.realm;

namespace wServer.networking.handlers
{
    class PotionsHandler : PacketHandlerBase<Potions>
    {
        private static readonly object PotionStorageLock = new object();
        public override PacketId ID => PacketId.POTIONS;

        protected override void HandlePacket(Client client, Potions packet)
        {
            client.Manager.Logic.AddPendingAction(t => Handle(client, packet, t));
        }

        private void Handle(Client client, Potions packet, RealmTime time)
        {
            var plr = client.Player;
            var acc = client.Account;
            if (plr == null || acc == null)
                return;

            lock (PotionStorageLock)
            {
                var potion = packet.Type;
                var classStats = plr.Manager.Resources.GameData.Classes[plr.ObjectType].Stats;
                var storage = acc.PotionStoragePotions;
                if (potion < 0 || potion >= classStats.Length || potion >= storage.Length)
                    return;

                var statCap = classStats[potion].MaxValue;
                var current = plr.Stats.Base[potion];
                if (current >= statCap)
                {
                    plr.SendInfo("This stat is already maxed!");
                    return;
                }

                // This is the same stat effect used by individual storage drinks:
                // Life and Mana grant five points; all other supported stats grant one.
                var pointsPerPotion = potion == 0 || potion == 1 ? 5 : 1;
                var consumption = PotionStorageConsumption.Resolve(
                    current, statCap, storage[potion], pointsPerPotion, packet.Max);
                var toConsume = consumption.PotionsConsumed;

                if (toConsume == 0)
                {
                    if (packet.Max)
                        plr.SendInfo("You don't have enough potions to max this stat.");
                    return;
                }

                plr.Stats.Base[potion] += consumption.StatPointsApplied;
                storage[potion] -= toConsume;
                acc.PotionStoragePotions = storage;
                acc.FlushAsync();

                // Persist the character side of the same operation immediately; queued
                // requests observe the updated authoritative values under this lock.
                plr.SaveToCharacter();
                client.Character.FlushAsync();

                if (packet.Max && toConsume < consumption.PotionsNeeded)
                    plr.SendInfo("You don't have enough potions to max this stat.");
            }
        }
    }
}
