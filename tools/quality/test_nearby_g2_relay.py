import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('relay', pathlib.Path(__file__).with_name('nearby_g2_relay.py'))
relay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(relay)


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.router = relay.Router('a' * 32)
        self.host = ('127.0.0.1', 30001)
        self.guest = ('127.0.0.1', 30002)

    def packet(self, role, payload=b'', token='a' * 32):
        return f'FG2|{token}|{role}|'.encode() + payload

    def test_registered_peers_forward_original_quic_bytes_both_ways(self):
        self.assertIsNone(self.router.route(self.host, self.packet('H')))
        self.assertIsNone(self.router.route(self.guest, self.packet('G')))
        data = bytes(range(256)) * 5
        self.assertEqual((self.guest, data), self.router.route(self.host, self.packet('H', data)))
        self.assertEqual((self.host, data[::-1]), self.router.route(self.guest, self.packet('G', data[::-1])))

    def test_wrong_registration_and_unexpected_peer_cannot_replace_routes(self):
        self.router.route(self.host, self.packet('H'))
        self.router.route(self.guest, self.packet('G'))
        for address, data in [
            (('127.0.0.1', 30003), self.packet('H', b'forged')),
            (self.host, self.packet('H', b'forged', 'b' * 32)),
            (('192.168.1.8', 30004), self.packet('G')),
            (self.host, b'not a registered packet'),
            (self.host, self.packet('X', b'unknown')),
            (self.host, self.packet('H', b'x' * 65508)),
        ]:
            self.assertIsNone(self.router.route(address, data))
        self.assertEqual((self.guest, b'ok'), self.router.route(self.host, self.packet('H', b'ok')))


if __name__ == '__main__':
    unittest.main()
