#!/usr/bin/env python3
"""Testes do builder de metadata packs. Nada aqui toca a rede."""
import gzip
import json
import sqlite3
import unittest

import build_metadata_pack as b

NO_INTRO_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
\tdescription "Nintendo - Super Nintendo Entertainment System"
)

game (
\tname "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
\tregion "Japan"
\trom ( name "'96 Zenkoku Koukou Soccer Senshuken (Japan).sfc" size 1572864 crc 05FBB855 md5 3369347F7663B133CE445C15200A5AFA sha1 005CCD8362DC41491F89F31FC9326A6688300E0C )
)
game (
\tname "Chrono Trigger (USA)"
\tregion "USA"
\trom ( name "Chrono Trigger (USA).sfc" size 4194304 crc 2D206BF7 md5 A2BC447961E52FD2227BAED164F729DC sha1 DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50 )
)
game (
\tname "Sem Hash (Japan)"
\tregion "Japan"
)
'''

REDUMP_DAT = '''clrmamepro (
\tname "Sony - PlayStation"
)

game (
\tname "'98 Koushien (Japan)"
\tregion "Japan"
\tserial "SLPS-01204"
\trom ( name "'98 Koushien (Japan).bin" size 583415952 crc 8ACD8FB1 md5 39A936EA7521157838D4E67B24F62F15 sha1 782C50827BF4CF8FE5530B64B188A2D43C75B0E0 serial "SLPS-01204" )
)
game (
\tname "'99 Koushien (Japan)"
\tregion "Japan"
\tserial "SLPS-02110"
\trom ( name "'99 Koushien (Japan) (Track 01).bin" size 314812848 crc 1D91CBAB md5 7BDC7092AEF04C6BEC7E78CDFE3D9A81 sha1 C1B7929C137E885569D30803664B26E496F32BB6 serial "SLPS-02110" )
\trom ( name "'99 Koushien (Japan) (Track 02).bin" size 12345 crc AAAAAAAA md5 BB sha1 CC serial "SLPS-02110" )
)
'''

GENRE_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
)

game (
\tcomment "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
\tgenre "Sports"
\trom ( crc 05FBB855 )
)
game (
\tcomment "Chrono Trigger (USA)"
\tgenre "Role-Playing"
\trom ( crc 2d206bf7 )
)
'''

SERIAL_DAT = '''game (
\tcomment "'96 Zenkoku Koukou Soccer Senshuken (Japan)"
\tserial "SHVC-AY2J-JPN"
\trom (
\t\tcrc 05FBB855
\t)
)
'''


class ParseDatTest(unittest.TestCase):
    def test_reads_every_game(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[1]["name"], "Chrono Trigger (USA)")

    def test_reads_the_first_rom_hashes_uppercased(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["crc"], "2D206BF7")
        self.assertEqual(entries[1]["sha1"], "DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50")

    def test_game_without_rom_line_keeps_null_hashes(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[2]["name"], "Sem Hash (Japan)")
        self.assertIsNone(entries[2]["crc"])
        self.assertIsNone(entries[2]["sha1"])

    def test_redump_serial_comes_from_the_game_block(self):
        entries = b.parse_dat(REDUMP_DAT)
        self.assertEqual(entries[0]["serial"], "SLPS-01204")

    def test_multitrack_redump_keeps_only_the_first_track(self):
        entries = b.parse_dat(REDUMP_DAT)
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[1]["crc"], "1D91CBAB")

    def test_no_intro_has_no_serial_in_the_main_dat(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertIsNone(entries[0]["serial"])


class ParseSideDatTest(unittest.TestCase):
    def test_maps_crc_to_value(self):
        side = b.parse_side_dat(GENRE_DAT, "genre")
        self.assertEqual(side["05FBB855"], "Sports")

    def test_crc_key_is_uppercased(self):
        side = b.parse_side_dat(GENRE_DAT, "genre")
        self.assertEqual(side["2D206BF7"], "Role-Playing")

    def test_handles_multiline_rom_blocks(self):
        side = b.parse_side_dat(SERIAL_DAT, "serial")
        self.assertEqual(side["05FBB855"], "SHVC-AY2J-JPN")

    def test_unknown_field_gives_an_empty_map(self):
        self.assertEqual(b.parse_side_dat(GENRE_DAT, "publisher"), {})


class SystemsTableTest(unittest.TestCase):
    def test_has_twenty_four_systems(self):
        self.assertEqual(len(b.SYSTEMS), 24)

    def test_pack_ids_are_unique_and_normalized(self):
        ids = [b.normalize(s["system"]) for s in b.SYSTEMS]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("nintendo_super_nintendo_entertainment_system", ids)

    def test_aliases_do_not_collide_across_systems(self):
        seen = {}
        for s in b.SYSTEMS:
            for alias in s["aliases"]:
                self.assertNotIn(alias, seen, f"{alias} repetido em {s['system']}")
                seen[alias] = s["system"]

    def test_every_system_declares_dat_group_and_thumbs(self):
        for s in b.SYSTEMS:
            self.assertIn(s["group"], ("no-intro", "redump"))
            self.assertTrue(s["thumbs"])

if __name__ == "__main__":
    unittest.main()
