using System;
using System.Collections.Generic;
using System.Linq;
using common.resources;
using wServer.networking.packets;
using wServer.networking.packets.incoming;
using wServer.networking.packets.outgoing;
using wServer.realm;
using wServer.realm.entities;

namespace wServer.networking.handlers
{
    class AcceptTradeHandler : PacketHandlerBase<AcceptTrade>
    {
        public override PacketId ID => PacketId.ACCEPTTRADE;

        protected override void HandlePacket(Client client, AcceptTrade packet)
        {
            //client.Manager.Logic.AddPendingAction(t => Handle(client, packet));
            Handle(client, packet);
        }

        private void Handle(Client client, AcceptTrade packet)
        {
            var player = client.Player;
            if (player == null || IsTest(client))
                return;
            if (player.tradeAccepted || player.tradeTarget == null || player.trade == null ||
                packet.MyOffer == null || packet.YourOffer == null ||
                packet.MyOffer.Length != 12 || packet.YourOffer.Length != 12)
            {
                Log.WarnFormat("[TRADE] rejected confirmation from player={0}: invalid or stale trade state.", player.Name);
                return;
            }

            player.trade = packet.MyOffer;
            if (player.tradeTarget.trade.SequenceEqual(packet.YourOffer))
            {
                player.tradeAccepted = true;
                Log.InfoFormat("[TRADE] first confirmation player={0} target={1}.", player.Name, player.tradeTarget.Name);
                player.tradeTarget.Client.SendPacket(new TradeAccepted()
                {
                    MyOffer = player.tradeTarget.trade,
                    YourOffer = player.trade
                });

                if (player.tradeAccepted && player.tradeTarget.tradeAccepted)
                {
                    DoTrade(player);
                }
            }
        }

        private void DoTrade(Player player)
        {
            var tradeTarget = player.tradeTarget;
            if (tradeTarget == null || player.Owner == null || tradeTarget.Owner == null || player.Owner != tradeTarget.Owner)
            {
                Fail(player, tradeTarget, "Trade participants are no longer in the same world.");
                return;
            }

            if (!player.tradeAccepted || !tradeTarget.tradeAccepted)
                return;

            var pInvTrans = player.Inventory.CreateTransaction();
            var tInvTrans = tradeTarget.Inventory.CreateTransaction();
            var offeredByPlayer = GetOfferedItems(player, pInvTrans);
            var offeredByTarget = GetOfferedItems(tradeTarget, tInvTrans);
            if (offeredByPlayer == null || offeredByTarget == null ||
                !PlaceItems(tInvTrans, offeredByPlayer) || !PlaceItems(pInvTrans, offeredByTarget))
            {
                Fail(player, tradeTarget, "Both players need enough free inventory space for this trade.");
                return;
            }

            if (!Inventory.Execute(pInvTrans, tInvTrans))
            {
                Fail(player, tradeTarget, "The inventory changed before the trade could be completed.");
                return;
            }
            if (!ItemInstanceTransferService.ApplyTransactions(pInvTrans, tInvTrans))
            {
                Inventory.Revert(pInvTrans, tInvTrans);
                Fail(player, tradeTarget, "The item identity transfer could not be committed.");
                return;
            }
            // Persist both character snapshots immediately after the single in-memory
            // transaction.  This matches the normal save path and closes the window
            // where a disconnect could reload a pre-trade inventory.
            player.SaveToCharacter();
            tradeTarget.SaveToCharacter();
            player.Client.Character.FlushAsync();
            tradeTarget.Client.Character.FlushAsync();
            Log.InfoFormat("[TRADE] completed player={0} target={1} sent={2} received={3}.",
                player.Name, tradeTarget.Name, offeredByPlayer.Count, offeredByTarget.Count);
            TradeDone(player, tradeTarget, "Trade Successful!");
        }

        private static List<Item> GetOfferedItems(Player player, InventoryTransaction transaction)
        {
            if (player.trade == null || player.trade.Length != 12)
                return null;
            var items = new List<Item>();
            for (var i = 4; i < 12; i++)
                if (player.trade[i])
                {
                    var item = transaction[i];
                    if (item == null || item.Soulbound)
                        return null;
                    items.Add(item);
                    transaction[i] = null;
                }
            return items;
        }

        private static bool PlaceItems(InventoryTransaction transaction, IEnumerable<Item> items)
        {
            foreach (var item in items)
            {
                var slot = transaction.GetAvailableInventorySlot(item);
                if (slot < 4)
                    return false;
                transaction[slot] = item;
            }
            return true;
        }

        private void Fail(Player player, Player target, string reason)
        {
            Log.WarnFormat("[TRADE] validation failure player={0} target={1}: {2}", player.Name, target?.Name, reason);
            TradeDone(player, target, "Trade unsuccessful: " + reason);
        }

        private void TradeDone(Player player, Player tradeTarget, string msg)
        {
            player.Client.SendPacket(new TradeDone
            {
                Code = 1,
                Description = msg
            });

            if (tradeTarget != null)
            {
                tradeTarget.Client.SendPacket(new TradeDone
                {
                    Code = 1,
                    Description = msg
                });
            }
            player.ResetTrade();
        }
    }
}
