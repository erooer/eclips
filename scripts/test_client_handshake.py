#!/usr/bin/env python3
"""Exercise the Flash wire protocol against a running isolated wServer."""

import argparse
import base64
import hashlib
import socket
import struct

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import padding


PUBLIC_KEY = b"""-----BEGIN PUBLIC KEY-----
MFswDQYJKoZIhvcNAQEBBQADSgAwRwJAeyjMOLhcK4o2AnFRhn8vPteUy5Fux/cX
N/J+wT/zYIEUINo02frn+Kyxx0RIXJ3CvaHkwmueVL8ytfqo8Ol/OwIDAQAB
-----END PUBLIC KEY-----"""


class Rc4:
    def __init__(self, key: bytes):
        self.s = list(range(256))
        j = 0
        for i in range(256):
            j = (j + self.s[i] + key[i % len(key)]) & 255
            self.s[i], self.s[j] = self.s[j], self.s[i]
        self.i = self.j = 0

    def crypt(self, data: bytes) -> bytes:
        result = bytearray(len(data))
        for n, value in enumerate(data):
            self.i = (self.i + 1) & 255
            self.j = (self.j + self.s[self.i]) & 255
            self.s[self.i], self.s[self.j] = self.s[self.j], self.s[self.i]
            result[n] = value ^ self.s[(self.s[self.i] + self.s[self.j]) & 255]
        return bytes(result)


def utf(value: str) -> bytes:
    raw = value.encode()
    return struct.pack(">H", len(raw)) + raw


def rsa(value: str) -> str:
    if not value:
        return ""
    key = serialization.load_pem_public_key(PUBLIC_KEY)
    encrypted = key.encrypt(value.encode(), padding.PKCS1v15())
    return base64.b64encode(encrypted).decode()


def read_exact(stream, length: int) -> bytes:
    result = bytearray()
    while len(result) < length:
        block = stream.recv(length - len(result))
        if not block:
            raise RuntimeError("wServer closed the socket during handshake")
        result.extend(block)
    return bytes(result)


def send_packet(stream, cipher: Rc4, packet_id: int, body: bytes) -> None:
    encrypted = cipher.crypt(body)
    stream.sendall(struct.pack(">IB", len(encrypted) + 5, packet_id) + encrypted)


def receive_packet(stream, cipher: Rc4):
    length, packet_id = struct.unpack(">IB", read_exact(stream, 5))
    return packet_id, cipher.crypt(read_exact(stream, length - 5))


def read_utf(body: bytes, offset: int):
    length = struct.unpack_from(">H", body, offset)[0]
    offset += 2
    return body[offset:offset + length].decode(), offset + length


def validate_map_info(body: bytes) -> None:
    offset = 8
    _, offset = read_utf(body, offset)
    _, offset = read_utf(body, offset)
    offset += 4 + 4 + 4 + 1 + 1 + 1 + 4
    for _ in range(2):
        count = struct.unpack_from(">h", body, offset)[0]
        offset += 2
        for _ in range(count):
            size = struct.unpack_from(">i", body, offset)[0]
            offset += 4 + size
    music, offset = read_utf(body, offset)
    if offset != len(body) or not music:
        raise RuntimeError("MAPINFO did not contain the client-compatible scalar music field")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2050)
    parser.add_argument("--guid", required=True)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    outgoing = Rc4(bytes.fromhex("B1A5ED"))
    incoming = Rc4(bytes.fromhex("612a806cac78114ba5013cb531"))
    hello = b"".join((
        utf("Release.2"), struct.pack(">i", -2), utf(rsa(args.guid)),
        utf(rsa(args.password)), utf(""), struct.pack(">iH", 0, 0),
        struct.pack(">i", 0), utf(rsa("ttp://")), utf(hashlib.md5(b"test").hexdigest()),
    ))

    with socket.create_connection((args.host, args.port), timeout=10) as stream:
        stream.settimeout(15)
        send_packet(stream, outgoing, 183, hello)
        map_info_seen = False
        for _ in range(12):
            packet_id, body = receive_packet(stream, incoming)
            if packet_id == 0:
                raise RuntimeError("wServer returned FAILURE during handshake")
            if packet_id == 74:
                validate_map_info(body)
                map_info_seen = True
                send_packet(stream, outgoing, 12, struct.pack(">HH", 0x030E, 0))
            elif packet_id == 81:
                if not map_info_seen:
                    raise RuntimeError("CREATE_SUCCESS arrived before MAPINFO")
                print("PASS: HELLO -> MAPINFO -> CREATE -> CREATE_SUCCESS reached Nexus-ready protocol state")
                return
        raise RuntimeError("Handshake did not reach CREATE_SUCCESS")


if __name__ == "__main__":
    main()
