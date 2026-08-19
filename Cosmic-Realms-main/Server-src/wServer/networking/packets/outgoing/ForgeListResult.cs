using common;
using System;
using System.Collections.Generic;

namespace wServer.networking.packets.outgoing
{
    public class ForgeListResult : OutgoingMessage
    {
        public override PacketId ID => PacketId.FORGE_LIST_RESULT;

        public string Result { get; set; }
        public List<string> Recipes { get; set; }
        public string ServiceKind { get; set; } = "legacy";
        public string Details { get; set; } = "";
        public string Command { get; set; } = "";
        public string ActionLabel { get; set; } = "";
        public bool Craftable { get; set; }

        public override Packet CreateInstance() => new ForgeListResult();

        protected override void Read(NReader rdr)
        {
            Result = rdr.ReadString();

            Recipes = new List<string>();
            for (var i = 0; i < rdr.ReadInt32(); i++)
                Recipes.Add(rdr.ReadString());
            ServiceKind = rdr.ReadString();
            Details = rdr.ReadString();
            Command = rdr.ReadString();
            ActionLabel = rdr.ReadString();
            Craftable = rdr.ReadBoolean();
        }

        protected override void Write(NWriter wtr)
        {
            wtr.WriteUTF(Result);
            wtr.Write(Recipes.Count);

            foreach (var r in Recipes)
                wtr.WriteUTF(r);
            wtr.WriteUTF(ServiceKind ?? "legacy");
            wtr.WriteUTF(Details ?? "");
            wtr.WriteUTF(Command ?? "");
            wtr.WriteUTF(ActionLabel ?? "");
            wtr.Write(Craftable);
        }
    }
}
