using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.IO;
using common;
using System.Net.Sockets;
using System.Net;
using wServer.networking.packets.outgoing;

namespace wServer.networking.packets
{
    public abstract class Packet
    {
        public static Dictionary<PacketId, Packet> Packets = new Dictionary<PacketId, Packet>();

        public Client Owner { get; private set; }

        static Packet()
        {
            foreach (var i in typeof(Packet).Assembly.GetTypes())
                if (typeof(Packet).IsAssignableFrom(i) && !i.IsAbstract)
                {
                    Packet pkt = (Packet)Activator.CreateInstance(i);
                    if (!(pkt is OutgoingMessage))
                        Packets.Add(pkt.ID, pkt);
                }
        }
        public abstract PacketId ID { get; }
        public abstract Packet CreateInstance();

        public void SetOwner(Client client)
        {
            Owner = client;
        }

        public abstract void Crypt(Client client, byte[] dat, int offset, int len);

        public void Read(Client client, byte[] body, int offset, int len)
        {
            Crypt(client, body, offset, len);
            try
            {
                Read(new NReader(new MemoryStream(body)));
            }
            catch (Exception error)
            {
                throw new InvalidDataException(
                    string.Format("Unable to decode {0} ({1}) while client was {2}; payload length={3}.",
                        ID, (byte)ID, client.State, len), error);
            }
        }

        public int Write(Client client, byte[] buff, int offset)
        {
            var s = new MemoryStream();
            Write(new NWriter(s));

            var bodyLength = (int) s.Position;
            var packetLength = bodyLength + 5;

            if (packetLength > buff.Length - offset)
                return 0;

            Buffer.BlockCopy(s.GetBuffer(), 0, buff, offset + 5, bodyLength);

            Crypt(client, buff, offset + 5, bodyLength);

            Buffer.BlockCopy(
                BitConverter.GetBytes(IPAddress.HostToNetworkOrder(packetLength)), 0,
                buff, offset, 4);

            buff[offset + 4] = (byte) ID;
            
            /*#if DEBUG
            Console.WriteLine($"Outbound packet detected!\nID: {ID}, Size: {packetLength} bytes");
            #endif DEBUG*/
            
            return packetLength;
        }

        // Serialization happens entirely in memory before a frame is appended to
        // the socket buffer. Callers use this to bound compound packets (UPDATE)
        // before queuing them, so an oversized frame cannot leave an initial world
        // synchronization in a partial state.
        public int GetFrameLength()
        {
            using (var s = new MemoryStream())
            {
                Write(new NWriter(s));
                return checked((int)s.Position + 5);
            }
        }

        protected abstract void Read(NReader rdr);
        protected abstract void Write(NWriter wtr);

        public override string ToString()
        {
            // buggy...
            var ret = new StringBuilder("{");
            var arr = GetType().GetProperties();
            for (var i = 0; i < arr.Length; i++)
            {
                if (i != 0) ret.Append(", ");
                ret.AppendFormat("{0}: {1}", arr[i].Name, arr[i].GetValue(this, null));
            }
            ret.Append("}");
            return ret.ToString();
        }
    }
}
