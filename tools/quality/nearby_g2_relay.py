"""Task-scoped simulator NAT relay; never a product network service."""
import argparse
import re
import socket
import time


class Router:
    def __init__(self, token):
        if not re.fullmatch(r'[a-f0-9]{32}', token):
            raise ValueError('A random 128-bit run token is required')
        self.token = token
        self.peers = {}

    def route(self, address, packet):
        if address[0] != '127.0.0.1' or len(packet) > 65507:
            return None
        fields = packet.split(b'|', 3)
        if len(fields) != 4 or fields[0] != b'FG2' or fields[1] != self.token.encode():
            return None
        role, payload = fields[2:]
        if role not in (b'H', b'G'):
            return None
        if role not in self.peers:
            if payload:
                return None
            self.peers[role] = address
        if self.peers[role] != address:
            return None
        other = self.peers.get(b'G' if role == b'H' else b'H')
        return (other, payload) if other is not None and payload else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--token', required=True)
    parser.add_argument('--seconds', type=int, default=180)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 600:
        parser.error('Lifetime must be 1..600 seconds')
    router = Router(args.token)
    packets = 0
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(('127.0.0.1', args.port))
        sock.settimeout(0.2)
        deadline = time.monotonic() + args.seconds
        print('READY loopback-only bounded UDP relay', flush=True)
        while time.monotonic() < deadline:
            try:
                packet, address = sock.recvfrom(65535)
            except socket.timeout:
                continue
            forwarded = router.route(address, packet)
            if forwarded:
                sock.sendto(forwarded[1], forwarded[0])
                packets += 1
        print(f'COMPLETE forwarded={packets} registered={len(router.peers)}', flush=True)


if __name__ == '__main__':
    main()
