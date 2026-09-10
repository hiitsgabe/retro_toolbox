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


class ThumbNameTest(unittest.TestCase):
    def test_keeps_the_dat_name_and_adds_png(self):
        self.assertEqual(b.thumb_name("Chrono Trigger (USA)"), "Chrono Trigger (USA).png")

    def test_replaces_the_characters_libretro_forbids(self):
        self.assertEqual(
            b.thumb_name("Advanced Dungeons & Dragons - Eye of the Beholder (USA)"),
            "Advanced Dungeons _ Dragons - Eye of the Beholder (USA).png",
        )
        self.assertEqual(b.thumb_name("Ratchet: Deadlocked"), "Ratchet_ Deadlocked.png")


class RegionPriorityTest(unittest.TestCase):
    def test_usa_beats_japan(self):
        self.assertLess(
            b.region_rank("Chrono Trigger (USA)"), b.region_rank("Chrono Trigger (Japan)")
        )

    def test_world_beats_europe(self):
        self.assertLess(
            b.region_rank("Sonic (World)"), b.region_rank("Sonic (Europe)")
        )

    def test_unknown_region_goes_last(self):
        self.assertGreater(
            b.region_rank("Sonic (Korea)"), b.region_rank("Sonic (Japan)")
        )


class AttachCoversTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/chrono-trigger",
            "title": "Chrono Trigger",
            "dumps": [
                {"name": "Chrono Trigger (Japan)", "crc": "1F2E3D4C"},
                {"name": "Chrono Trigger (USA)", "crc": "2D206BF7"},
            ],
        }]

    def test_picks_the_preferred_region_cover(self):
        games = self.games()
        available = {"Chrono Trigger (Japan).png", "Chrono Trigger (USA).png"}
        b.attach_thumbnail_covers(games, available, "Nintendo_-_Super_Nintendo_Entertainment_System")
        self.assertEqual(
            games[0]["cover"],
            "https://raw.githubusercontent.com/libretro-thumbnails/"
            "Nintendo_-_Super_Nintendo_Entertainment_System/master/Named_Boxarts/"
            "Chrono%20Trigger%20%28USA%29.png",
        )

    def test_falls_back_to_the_only_available_region(self):
        games = self.games()
        b.attach_thumbnail_covers(games, {"Chrono Trigger (Japan).png"}, "R")
        self.assertIn("Japan", games[0]["cover"])

    def test_no_thumbnail_leaves_the_game_without_cover(self):
        games = self.games()
        b.attach_thumbnail_covers(games, set(), "R")
        self.assertNotIn("cover", games[0])


class OpenVgdbTest(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.executescript('''
            CREATE TABLE ROMs (romID INTEGER, romHashCRC TEXT);
            CREATE TABLE RELEASES (romID INTEGER, releaseDescription TEXT,
                releaseCoverFront TEXT, releaseDeveloper TEXT,
                releasePublisher TEXT, releaseGenre TEXT, releaseDate TEXT);
            INSERT INTO ROMs VALUES (1, '2D206BF7');
            INSERT INTO RELEASES VALUES (1, 'Um RPG.', 'https://img/ct.jpg',
                'Square', 'Square', 'Role-Playing', 'Mar 11, 1995');
            INSERT INTO ROMs VALUES (2, 'AAAAAAAA');
            INSERT INTO RELEASES VALUES (2, NULL, NULL, NULL, NULL, NULL, NULL);
        ''')

    def test_index_is_keyed_by_uppercase_crc(self):
        index = b.openvgdb_index(self.conn)
        self.assertIn("2D206BF7", index)
        self.assertEqual(index["2D206BF7"]["synopsis"], "Um RPG.")

    def test_year_is_extracted_from_the_release_date(self):
        index = b.openvgdb_index(self.conn)
        self.assertEqual(index["2D206BF7"]["year"], 1995)

    def test_rows_without_any_useful_field_are_skipped(self):
        self.assertNotIn("AAAAAAAA", b.openvgdb_index(self.conn))

    def test_enrich_fills_only_what_is_missing(self):
        games = [{
            "id": "snes/chrono-trigger", "title": "Chrono Trigger",
            "genre": "RPG",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["genre"], "RPG")
        self.assertEqual(games[0]["synopsis"], "Um RPG.")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_openvgdb_cover_is_only_a_fallback(self):
        games = [{
            "id": "a", "title": "A", "cover": "https://libretro/x.png",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://libretro/x.png")

    def test_openvgdb_cover_is_used_when_there_is_none(self):
        games = [{
            "id": "a", "title": "A",
            "dumps": [{"name": "Chrono Trigger (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://img/ct.jpg")


class BuildPackTest(unittest.TestCase):
    def test_assembles_the_pack_document(self):
        pack = b.build_pack(
            system={"system": "Nintendo - Super Nintendo Entertainment System",
                    "group": "no-intro",
                    "thumbs": "Nintendo_-_Super_Nintendo_Entertainment_System",
                    "aliases": ["snes"]},
            dat_text=NO_INTRO_DAT,
            side_texts={"genre": GENRE_DAT, "serial": SERIAL_DAT},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        self.assertEqual(pack["pack"], "nintendo_super_nintendo_entertainment_system")
        self.assertEqual(pack["system"], "Nintendo - Super Nintendo Entertainment System")
        self.assertEqual(pack["built"], "2026-09-10")
        self.assertEqual(len(pack["games"]), 3)

    def test_side_data_reaches_the_games(self):
        pack = b.build_pack(
            system={"system": "Nintendo - Super Nintendo Entertainment System",
                    "group": "no-intro", "thumbs": "T", "aliases": []},
            dat_text=NO_INTRO_DAT,
            side_texts={"genre": GENRE_DAT, "serial": SERIAL_DAT},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        by_id = {g["id"]: g for g in pack["games"]}
        chrono = by_id["nintendo_super_nintendo_entertainment_system/chrono-trigger"]
        self.assertEqual(chrono["genre"], "Role-Playing")

    def test_missing_side_files_are_tolerated(self):
        pack = b.build_pack(
            system={"system": "Sony - PlayStation", "group": "redump",
                    "thumbs": "T", "aliases": []},
            dat_text=REDUMP_DAT,
            side_texts={},
            thumbs=set(),
            openvgdb={},
            built="2026-09-10",
        )
        self.assertEqual(len(pack["games"]), 2)
        self.assertEqual(pack["games"][0]["dumps"][0]["serial"], "SLPS-01204")


class WritePackTest(unittest.TestCase):
    def test_gzip_round_trips_and_is_deterministic(self):
        pack = {"pack": "snes", "system": "S", "built": "2026-09-10", "games": []}
        first = b.pack_bytes(pack)
        second = b.pack_bytes(pack)
        self.assertEqual(first, second)
        self.assertEqual(json.loads(gzip.decompress(first).decode("utf-8")), pack)


class BuildIndexTest(unittest.TestCase):
    def test_index_carries_pack_system_count_and_aliases(self):
        packs = [{"pack": "snes", "system": "Nintendo - Super Nintendo Entertainment System",
                  "built": "2026-09-10", "games": [{"id": "a"}, {"id": "b"}]}]
        aliases = {"snes": ["super_nintendo", "snes"]}
        index = b.build_index(packs, aliases, "2026-09-10")
        self.assertEqual(index["built"], "2026-09-10")
        self.assertEqual(index["packs"], [{
            "pack": "snes",
            "system": "Nintendo - Super Nintendo Entertainment System",
            "games": 2,
            "aliases": ["super_nintendo", "snes"],
        }])

    def test_empty_pack_list_still_produces_a_valid_index(self):
        self.assertEqual(b.build_index([], {}, "2026-09-10"),
                         {"built": "2026-09-10", "packs": []})


if __name__ == "__main__":
    unittest.main()
