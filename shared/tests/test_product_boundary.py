"""Guard the catalog product leaf/public ABI against platform/runtime coupling."""
import pathlib
import re
import unittest

SHARED = pathlib.Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(r'(?:flutter|jni|arkts|napi|node_api|sqlite|quic|nes_core|flynes_runtime|flynes_session|[/\\]core[/\\])', re.I)


def dependencies(text):
    return re.findall(r'^\s*#\s*include\s*[<"]([^>"\n]+)', text, re.M)


def private_shared_import(dependency):
    normalized = dependency.replace('\\', '/')
    return ('shared/src/' in normalized or
            (SHARED / 'src' / normalized).is_file())


class ProductBoundaryTests(unittest.TestCase):
    def test_public_header_is_c_and_only_uses_neutral_abi(self):
        header = (SHARED / 'include/flynes/flynes_product.h').read_text(encoding='utf-8')
        self.assertEqual(dependencies(header), ['flynes/flynes_app.h'])
        old_header = (SHARED / 'include/flynes/flynes_app.h').read_text(encoding='utf-8')
        self.assertEqual(dependencies(old_header), ['stddef.h', 'stdint.h'])

    def test_catalog_rules_remain_a_leaf(self):
        for path in [
            'include/flynes/product/game_center_item.hpp',
            'include/flynes/product/game_center_state.hpp',
            'include/flynes/product/multiplayer_eligibility.hpp',
            'src/product/game_center_state.cpp',
            'src/product/multiplayer_eligibility.cpp',
        ]:
            for dependency in dependencies((SHARED / path).read_text(encoding='utf-8')):
                self.assertIsNone(FORBIDDEN.search(dependency), f'{path}: {dependency}')
        cmake = (SHARED / 'CMakeLists.txt').read_text(encoding='utf-8')
        self.assertNotRegex(cmake, r'target_link_libraries\(flynes_product\s')

    def test_guard_rejects_dependency_regressions(self):
        for dependency in ['jni.h', 'flutter/method_channel.h', 'napi/native_api.h',
                           'flynes/flynes_runtime.h', 'core/nes_core.h', 'sqlite3.h']:
            self.assertIsNotNone(FORBIDDEN.search(dependency))

    def test_product_adapters_only_import_shared_public_headers(self):
        root = SHARED.parent
        paths = [root / 'app/src/main/cpp/flynes_app_jni.cpp']
        paths += list((root / 'harmony/entry/src/main/cpp').glob('product_catalog*.*pp'))
        self.assertGreaterEqual(len(paths), 5)
        for path in paths:
            for dependency in dependencies(path.read_text(encoding='utf-8')):
                self.assertFalse(private_shared_import(dependency), f'{path.name}: {dependency}')

    def test_private_header_guard_detects_relative_and_include_root_imports(self):
        for dependency in ['../../shared/src/app/catalog_snapshot.hpp',
                           'app/catalog_snapshot.hpp', 'catalog/content_identity.hpp']:
            self.assertTrue(private_shared_import(dependency), dependency)
        for dependency in ['flynes/flynes_product.h', 'flynes/flynes_app.h',
                           'product_catalog_projection.hpp', 'vector']:
            self.assertFalse(private_shared_import(dependency), dependency)


if __name__ == '__main__':
    unittest.main()
