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


class NormTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(b.norm("Chrono Trigger (USA)"), "chrono trigger (usa)")

    def test_expands_ampersand(self):
        self.assertEqual(b.norm("Dig & Spike"), "dig and spike")

    def test_drops_accents(self):
        self.assertEqual(b.norm("Pokémon Rojo"), "pokemon rojo")

    def test_strips_rom_extensions(self):
        self.assertEqual(b.norm("Chrono Trigger (USA).sfc"), "chrono trigger (usa)")
        self.assertEqual(b.norm("Chrono Trigger (USA).zip"), "chrono trigger (usa)")


class CanonTest(unittest.TestCase):
    def test_drops_region_and_revision_tags(self):
        self.assertEqual(b.canon("Chrono Trigger (USA) (Rev 1)"), "chrono trigger")
        self.assertEqual(b.canon("Chrono Trigger (Japan) [T+Eng]"), "chrono trigger")

    def test_moves_the_trailing_article_to_the_front(self):
        self.assertEqual(b.canon("Legend of Zelda, The (USA)"), "the legend of zelda")

    def test_different_regions_share_one_canon(self):
        self.assertEqual(
            b.canon("Super Mario World (USA)"), b.canon("Super Mario World (Europe)")
        )


class DisplayTitleTest(unittest.TestCase):
    def test_keeps_the_original_casing(self):
        self.assertEqual(b.display_title("Chrono Trigger (USA)"), "Chrono Trigger")

    def test_moves_the_article_without_lowercasing_the_rest(self):
        self.assertEqual(
            b.display_title("Legend of Zelda, The (USA)"), "The Legend of Zelda"
        )

    def test_keeps_accents_and_punctuation(self):
        self.assertEqual(b.display_title("Pokémon Rojo (Spain).gb"), "Pokémon Rojo")

    def test_name_that_is_only_tags_becomes_empty(self):
        self.assertEqual(b.display_title("(USA)"), "")


class SlugTest(unittest.TestCase):
    def test_makes_a_url_safe_slug(self):
        self.assertEqual(b.slug("the legend of zelda"), "the-legend-of-zelda")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(b.slug("f-zero  ii!!"), "f-zero-ii")


class CollapseTest(unittest.TestCase):
    def setUp(self):
        self.entries = [
            {"name": "Chrono Trigger (USA)", "crc": "2D206BF7", "sha1": "A", "serial": None},
            {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C", "sha1": "B", "serial": None},
            {"name": "Legend of Zelda, The (USA)", "crc": "AAAAAAAA", "sha1": None, "serial": None},
        ]

    def test_dumps_of_the_same_game_collapse_into_one_entry(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(len(games), 2)
        self.assertEqual(len(games[0]["dumps"]), 2)

    def test_title_comes_from_the_first_dump_without_its_tags(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["title"], "Chrono Trigger")
        self.assertEqual(games[1]["title"], "The Legend of Zelda")

    def test_id_is_pack_slash_slug(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["id"], "snes/chrono-trigger")
        self.assertEqual(games[1]["id"], "snes/the-legend-of-zelda")

    def test_dump_order_is_the_dat_order(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(
            [d["name"] for d in games[0]["dumps"]],
            ["Chrono Trigger (USA)", "Chrono Trigger (Japan)"],
        )

    def test_hyphen_and_space_spellings_are_the_same_game(self):
        entries = [
            {"name": "Pac-Man (USA)", "crc": "1", "sha1": None, "serial": None},
            {"name": "Pac Man (Japan)", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "nes")
        self.assertEqual(len(games), 1)
        self.assertEqual(games[0]["id"], "nes/pac-man")

    def test_two_titles_with_the_same_slug_get_a_numeric_suffix(self):
        # Tags desbalanceadas sobrevivem ao canon, entao dois jogos de canon
        # diferente podem cair no mesmo slug. O sufixo garante id único.
        entries = [
            {"name": "Sonic (Beta", "crc": "1", "sha1": None, "serial": None},
            {"name": "Sonic Beta", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "md")
        self.assertEqual(len(games), 2)
        self.assertEqual(games[0]["id"], "md/sonic-beta")
        self.assertEqual(games[1]["id"], "md/sonic-beta-2")

    def test_entries_without_a_canon_title_are_dropped(self):
        entries = [{"name": "(USA)", "crc": "1", "sha1": None, "serial": None}]
        self.assertEqual(b.collapse(entries, "nes"), [])


class EnrichTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/chrono-trigger",
            "title": "Chrono Trigger",
            "dumps": [
                {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C"},
                {"name": "Chrono Trigger (USA)", "crc": "2D206BF7"},
            ],
        }]

    def test_fills_the_fields_from_the_side_maps(self):
        games = self.games()
        b.enrich_from_side(games, {
            "genre": {"2D206BF7": "Role-Playing"},
            "developer": {"2D206BF7": "Square"},
            "publisher": {"2D206BF7": "Square"},
            "releaseyear": {"2D206BF7": "1995"},
        })
        self.assertEqual(games[0]["genre"], "Role-Playing")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["publisher"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_the_first_dump_with_a_value_wins(self):
        games = self.games()
        b.enrich_from_side(games, {
            "genre": {"1F2E3D4C": "Action", "2D206BF7": "Role-Playing"},
        })
        self.assertEqual(games[0]["genre"], "Action")

    def test_serial_lands_on_the_dump_not_on_the_game(self):
        games = self.games()
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertNotIn("serial", games[0])
        self.assertEqual(games[0]["dumps"][1]["serial"], "SNS-AC-USA")

    def test_serial_already_on_the_dump_is_not_overwritten(self):
        games = self.games()
        games[0]["dumps"][1]["serial"] = "JA-ESTAVA-LA"
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertEqual(games[0]["dumps"][1]["serial"], "JA-ESTAVA-LA")

    def test_missing_side_maps_leave_the_game_untouched(self):
        games = self.games()
        b.enrich_from_side(games, {})
        self.assertEqual(set(games[0]), {"id", "title", "dumps"})

    def test_non_numeric_year_is_ignored(self):
        games = self.games()
        b.enrich_from_side(games, {"releaseyear": {"2D206BF7": "199x"}})
        self.assertNotIn("year", games[0])

    def test_franchise_and_esrb_are_carried_over(self):
        games = self.games()
        b.enrich_from_side(games, {
            "franchise": {"2D206BF7": "Chrono"},
            "esrb": {"2D206BF7": "E"},
        })
        self.assertEqual(games[0]["franchise"], "Chrono")
        self.assertEqual(games[0]["esrb"], "E")

if __name__ == "__main__":
    unittest.main()
