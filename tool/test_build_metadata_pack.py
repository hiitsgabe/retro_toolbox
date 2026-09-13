#!/usr/bin/env python3
"""Tests for the metadata pack builder. Nothing here touches the network."""
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
\tname "'96 Zenith Cup Soccer (Japan)"
\tregion "Japan"
\trom ( name "'96 Zenith Cup Soccer (Japan).sfc" size 1572864 crc 05FBB855 md5 3369347F7663B133CE445C15200A5AFA sha1 005CCD8362DC41491F89F31FC9326A6688300E0C )
)
game (
\tname "Crystal Vanguard (USA)"
\tregion "USA"
\trom ( name "Crystal Vanguard (USA).sfc" size 4194304 crc 2D206BF7 md5 A2BC447961E52FD2227BAED164F729DC sha1 DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50 )
)
game (
\tname "No Hash (Japan)"
\tregion "Japan"
)
'''

REDUMP_DAT = '''clrmamepro (
\tname "Sony - PlayStation"
)

game (
\tname "'98 Ballpark (Japan)"
\tregion "Japan"
\tserial "SLPS-01204"
\trom ( name "'98 Ballpark (Japan).bin" size 583415952 crc 8ACD8FB1 md5 39A936EA7521157838D4E67B24F62F15 sha1 782C50827BF4CF8FE5530B64B188A2D43C75B0E0 serial "SLPS-01204" )
)
game (
\tname "'99 Ballpark (Japan)"
\tregion "Japan"
\tserial "SLPS-02110"
\trom ( name "'99 Ballpark (Japan) (Track 01).bin" size 314812848 crc 1D91CBAB md5 7BDC7092AEF04C6BEC7E78CDFE3D9A81 sha1 C1B7929C137E885569D30803664B26E496F32BB6 serial "SLPS-02110" )
\trom ( name "'99 Ballpark (Japan) (Track 02).bin" size 12345 crc AAAAAAAA md5 BB sha1 CC serial "SLPS-02110" )
)
'''

GENRE_DAT = '''clrmamepro (
\tname "Nintendo - Super Nintendo Entertainment System"
)

game (
\tcomment "'96 Zenith Cup Soccer (Japan)"
\tgenre "Sports"
\trom ( crc 05FBB855 )
)
game (
\tcomment "Crystal Vanguard (USA)"
\tgenre "Role-Playing"
\trom ( crc 2d206bf7 )
)
'''

SERIAL_DAT = '''game (
\tcomment "'96 Zenith Cup Soccer (Japan)"
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
        self.assertEqual(entries[1]["name"], "Crystal Vanguard (USA)")

    def test_reads_the_first_rom_hashes_uppercased(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["crc"], "2D206BF7")
        self.assertEqual(entries[1]["sha1"], "DE5DFB1E9F82A5C1220E7C6D0D4E5F5C2D3E4F50")

    def test_game_without_rom_line_keeps_null_hashes(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[2]["name"], "No Hash (Japan)")
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

    def test_region_is_read_and_is_optional(self):
        entries = b.parse_dat(NO_INTRO_DAT)
        self.assertEqual(entries[1]["region"], "USA")
        self.assertEqual(entries[0]["region"], "Japan")
        untagged = b.parse_dat('game (\n\tname "No Region"\n)\n')
        self.assertIsNone(untagged[0]["region"])


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
                self.assertNotIn(alias, seen, f"{alias} repeated in {s['system']}")
                seen[alias] = s["system"]

    def test_every_system_declares_dat_group_and_thumbs(self):
        for s in b.SYSTEMS:
            self.assertIn(s["group"], ("no-intro", "redump"))
            self.assertTrue(s["thumbs"])


class NormTest(unittest.TestCase):
    def test_lowercases_and_strips_punctuation(self):
        self.assertEqual(b.norm("Crystal Vanguard (USA)"), "crystal vanguard (usa)")

    def test_expands_ampersand(self):
        self.assertEqual(b.norm("Grip & Slam"), "grip and slam")

    def test_drops_accents(self):
        self.assertEqual(b.norm("Prismón Rojo"), "prismon rojo")

    def test_strips_rom_extensions(self):
        self.assertEqual(b.norm("Crystal Vanguard (USA).sfc"), "crystal vanguard (usa)")
        self.assertEqual(b.norm("Crystal Vanguard (USA).zip"), "crystal vanguard (usa)")


class CanonTest(unittest.TestCase):
    def test_drops_region_and_revision_tags(self):
        self.assertEqual(b.canon("Crystal Vanguard (USA) (Rev 1)"), "crystal vanguard")
        self.assertEqual(b.canon("Crystal Vanguard (Japan) [T+Eng]"), "crystal vanguard")

    def test_moves_the_trailing_article_to_the_front(self):
        self.assertEqual(b.canon("Legend of Kaelis, The (USA)"), "the legend of kaelis")

    def test_different_regions_share_one_canon(self):
        self.assertEqual(
            b.canon("Super Pixel World (USA)"), b.canon("Super Pixel World (Europe)")
        )


class DisplayTitleTest(unittest.TestCase):
    def test_keeps_the_original_casing(self):
        self.assertEqual(b.display_title("Crystal Vanguard (USA)"), "Crystal Vanguard")

    def test_moves_the_article_without_lowercasing_the_rest(self):
        self.assertEqual(
            b.display_title("Legend of Kaelis, The (USA)"), "The Legend of Kaelis"
        )

    def test_keeps_accents_and_punctuation(self):
        self.assertEqual(b.display_title("Prismón Rojo (Spain).gb"), "Prismón Rojo")

    def test_name_that_is_only_tags_becomes_empty(self):
        self.assertEqual(b.display_title("(USA)"), "")


class SlugTest(unittest.TestCase):
    def test_makes_a_url_safe_slug(self):
        self.assertEqual(b.slug("the legend of kaelis"), "the-legend-of-kaelis")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(b.slug("f-blaze  ii!!"), "f-blaze-ii")


class CollapseTest(unittest.TestCase):
    def setUp(self):
        self.entries = [
            {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7", "sha1": "A",
             "serial": None, "region": "USA"},
            {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C", "sha1": "B",
             "serial": None, "region": "Japan"},
            {"name": "Legend of Kaelis, The (USA)", "crc": "AAAAAAAA", "sha1": None,
             "serial": None, "region": None},
        ]

    def test_dumps_of_the_same_game_collapse_into_one_entry(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(len(games), 2)
        self.assertEqual(len(games[0]["dumps"]), 2)

    def test_title_comes_from_the_first_dump_without_its_tags(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["title"], "Crystal Vanguard")
        self.assertEqual(games[1]["title"], "The Legend of Kaelis")

    def test_id_is_pack_slash_slug(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["id"], "snes/crystal-vanguard")
        self.assertEqual(games[1]["id"], "snes/the-legend-of-kaelis")

    def test_dump_order_is_the_dat_order(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(
            [d["name"] for d in games[0]["dumps"]],
            ["Crystal Vanguard (USA)", "Crystal Vanguard (Japan)"],
        )

    def test_hyphen_and_space_spellings_are_the_same_game(self):
        entries = [
            {"name": "Pix-Man (USA)", "crc": "1", "sha1": None, "serial": None},
            {"name": "Pix Man (Japan)", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "nes")
        self.assertEqual(len(games), 1)
        self.assertEqual(games[0]["id"], "nes/pix-man")

    def test_two_titles_with_the_same_slug_get_a_numeric_suffix(self):
        entries = [
            {"name": "Sprint (Beta", "crc": "1", "sha1": None, "serial": None},
            {"name": "Sprint Beta", "crc": "2", "sha1": None, "serial": None},
        ]
        games = b.collapse(entries, "md")
        self.assertEqual(len(games), 2)
        self.assertEqual(games[0]["id"], "md/sprint-beta")
        self.assertEqual(games[1]["id"], "md/sprint-beta-2")

    def test_region_travels_to_the_dump_and_is_omitted_when_absent(self):
        games = b.collapse(self.entries, "snes")
        self.assertEqual(games[0]["dumps"][0]["region"], "USA")
        self.assertEqual(games[0]["dumps"][1]["region"], "Japan")
        self.assertNotIn("region", games[1]["dumps"][0])

    def test_entries_without_a_canon_title_are_dropped(self):
        entries = [{"name": "(USA)", "crc": "1", "sha1": None, "serial": None}]
        self.assertEqual(b.collapse(entries, "nes"), [])


class EnrichTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/crystal-vanguard",
            "title": "Crystal Vanguard",
            "dumps": [
                {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C"},
                {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"},
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
        games[0]["dumps"][1]["serial"] = "ALREADY-THERE"
        b.enrich_from_side(games, {"serial": {"2D206BF7": "SNS-AC-USA"}})
        self.assertEqual(games[0]["dumps"][1]["serial"], "ALREADY-THERE")

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
            "franchise": {"2D206BF7": "Crystal"},
            "esrb": {"2D206BF7": "E"},
        })
        self.assertEqual(games[0]["franchise"], "Crystal")
        self.assertEqual(games[0]["esrb"], "E")


class ThumbNameTest(unittest.TestCase):
    def test_keeps_the_dat_name_and_adds_png(self):
        self.assertEqual(b.thumb_name("Crystal Vanguard (USA)"), "Crystal Vanguard (USA).png")

    def test_replaces_the_characters_libretro_forbids(self):
        self.assertEqual(
            b.thumb_name("Guild & Dungeon - Eye of the Watcher (USA)"),
            "Guild _ Dungeon - Eye of the Watcher (USA).png",
        )
        self.assertEqual(b.thumb_name("Sprocket: Deadlocked"), "Sprocket_ Deadlocked.png")


class RegionPriorityTest(unittest.TestCase):
    def test_usa_beats_japan(self):
        self.assertLess(
            b.region_rank("Crystal Vanguard (USA)"), b.region_rank("Crystal Vanguard (Japan)")
        )

    def test_world_beats_europe(self):
        self.assertLess(
            b.region_rank("Sprint (World)"), b.region_rank("Sprint (Europe)")
        )

    def test_unknown_region_goes_last(self):
        self.assertGreater(
            b.region_rank("Sprint (Korea)"), b.region_rank("Sprint (Japan)")
        )


class AttachCoversTest(unittest.TestCase):
    def games(self):
        return [{
            "id": "snes/crystal-vanguard",
            "title": "Crystal Vanguard",
            "dumps": [
                {"name": "Crystal Vanguard (Japan)", "crc": "1F2E3D4C"},
                {"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"},
            ],
        }]

    def attach(self, games, available, repo="R", field="cover"):
        b.attach_thumbnails(games, available, repo, b.THUMB_FOLDERS[field], field)

    def test_picks_the_preferred_region_cover(self):
        games = self.games()
        available = {"Crystal Vanguard (Japan).png", "Crystal Vanguard (USA).png"}
        self.attach(games, available, "Nintendo_-_Super_Nintendo_Entertainment_System")
        self.assertEqual(
            games[0]["cover"],
            "https://raw.githubusercontent.com/libretro-thumbnails/"
            "Nintendo_-_Super_Nintendo_Entertainment_System/master/Named_Boxarts/"
            "Crystal%20Vanguard%20%28USA%29.png",
        )

    def test_falls_back_to_the_only_available_region(self):
        games = self.games()
        self.attach(games, {"Crystal Vanguard (Japan).png"})
        self.assertIn("Japan", games[0]["cover"])

    def test_no_thumbnail_leaves_the_game_without_cover(self):
        games = self.games()
        self.attach(games, set())
        self.assertNotIn("cover", games[0])

    def test_a_screenshot_lands_in_its_own_field_and_folder(self):
        games = self.games()
        self.attach(games, {"Crystal Vanguard (USA).png"}, field="screenshot")
        self.assertIn("/Named_Snaps/", games[0]["screenshot"])
        self.assertNotIn("cover", games[0])

    def test_the_title_screen_has_its_own_folder(self):
        games = self.games()
        self.attach(games, {"Crystal Vanguard (USA).png"}, field="titleScreen")
        self.assertIn("/Named_Titles/", games[0]["titleScreen"])

    def test_each_folder_resolves_its_own_region(self):
        # The folders do not hold the same files, so the game can end up with a
        # USA cover and a Japan screenshot. Reusing the cover's dump would have
        # left the screenshot missing instead.
        games = self.games()
        self.attach(games, {"Crystal Vanguard (USA).png"})
        self.attach(games, {"Crystal Vanguard (Japan).png"}, field="screenshot")
        self.assertIn("USA", games[0]["cover"])
        self.assertIn("Japan", games[0]["screenshot"])


class OpenVgdbTest(unittest.TestCase):
    def setUp(self):
        self.conn = sqlite3.connect(":memory:")
        self.conn.executescript('''
            CREATE TABLE ROMs (romID INTEGER, romHashCRC TEXT, romSerial TEXT);
            CREATE TABLE RELEASES (romID INTEGER, releaseDescription TEXT,
                releaseCoverFront TEXT, releaseDeveloper TEXT,
                releasePublisher TEXT, releaseGenre TEXT, releaseDate TEXT);
            INSERT INTO ROMs VALUES (1, '2D206BF7', 'SNS-AC-USA');
            INSERT INTO RELEASES VALUES (1, 'An RPG.', 'https://img/ct.jpg',
                'Square', 'Square', 'Role-Playing', 'Mar 11, 1995');
            INSERT INTO ROMs VALUES (2, 'AAAAAAAA', NULL);
            INSERT INTO RELEASES VALUES (2, NULL, NULL, NULL, NULL, NULL, NULL);
            INSERT INTO ROMs VALUES (3, 'BBBBBBBB', 'SLUS-01272');
            INSERT INTO RELEASES VALUES (3, 'A shooter.', NULL, 'Black Ops',
                NULL, 'Action', 'Nov 6, 2000');
        ''')

    def test_index_is_keyed_by_uppercase_crc(self):
        index = b.openvgdb_index(self.conn)
        self.assertIn("2D206BF7", index)
        self.assertEqual(index["2D206BF7"]["synopsis"], "An RPG.")

    def test_year_is_extracted_from_the_release_date(self):
        index = b.openvgdb_index(self.conn)
        self.assertEqual(index["2D206BF7"]["year"], 1995)

    def test_rows_without_any_useful_field_are_skipped(self):
        self.assertNotIn("AAAAAAAA", b.openvgdb_index(self.conn))

    def test_enrich_fills_only_what_is_missing(self):
        games = [{
            "id": "snes/crystal-vanguard", "title": "Crystal Vanguard",
            "genre": "RPG",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["genre"], "RPG")
        self.assertEqual(games[0]["synopsis"], "An RPG.")
        self.assertEqual(games[0]["developer"], "Square")
        self.assertEqual(games[0]["year"], 1995)

    def test_openvgdb_cover_is_only_a_fallback(self):
        games = [{
            "id": "a", "title": "A", "cover": "https://libretro/x.png",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://libretro/x.png")

    def test_openvgdb_cover_is_used_when_there_is_none(self):
        games = [{
            "id": "a", "title": "A",
            "dumps": [{"name": "Crystal Vanguard (USA)", "crc": "2D206BF7"}],
        }]
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertEqual(games[0]["cover"], "https://img/ct.jpg")


class OpenVgdbSerialTest(OpenVgdbTest):
    """The disc systems, whose DAT CRC never meets the OpenVGDB CRC."""

    def indexes(self):
        return b.openvgdb_index(self.conn), b.openvgdb_serial_index(self.conn)

    def disc(self, **dump):
        return [{"id": "psx/a", "title": "A", "dumps": [dump]}]

    def test_the_index_is_keyed_by_uppercase_serial(self):
        index = b.openvgdb_serial_index(self.conn)
        self.assertIn("SLUS-01272", index)
        self.assertEqual(index["SLUS-01272"]["synopsis"], "A shooter.")

    def test_a_serial_without_any_useful_field_is_skipped(self):
        self.assertNotIn(None, b.openvgdb_serial_index(self.conn))

    def test_a_disc_with_an_unmatched_crc_is_filled_by_serial(self):
        games = self.disc(name="Bond (USA)", crc="DEADBEEF", serial="SLUS-01272")
        b.enrich_from_openvgdb(games, *self.indexes())
        self.assertEqual(games[0]["synopsis"], "A shooter.")
        self.assertEqual(games[0]["developer"], "Black Ops")
        self.assertEqual(games[0]["year"], 2000)

    def test_the_serial_is_matched_case_insensitively(self):
        games = self.disc(name="Bond (USA)", crc="DEADBEEF", serial="slus-01272")
        b.enrich_from_openvgdb(games, *self.indexes())
        self.assertEqual(games[0]["synopsis"], "A shooter.")

    def test_crc_wins_over_serial(self):
        # CRC names one exact dump and the serial names a release, so a dump
        # carrying both must come back with the CRC record.
        games = self.disc(name="A (USA)", crc="2D206BF7", serial="SLUS-01272")
        b.enrich_from_openvgdb(games, *self.indexes())
        self.assertEqual(games[0]["synopsis"], "An RPG.")

    def test_a_later_dump_supplies_the_serial(self):
        games = [{"id": "psx/a", "title": "A", "dumps": [
            {"name": "A (Japan)", "crc": "DEADBEEF", "serial": "SLPS-99999"},
            {"name": "A (USA)", "crc": "DEADBEEF", "serial": "SLUS-01272"},
        ]}]
        b.enrich_from_openvgdb(games, *self.indexes())
        self.assertEqual(games[0]["synopsis"], "A shooter.")

    def test_without_a_serial_index_nothing_changes(self):
        # The cartridge systems keep calling with CRC only, and must not start
        # picking up serial records by accident.
        games = self.disc(name="Bond (USA)", crc="DEADBEEF", serial="SLUS-01272")
        b.enrich_from_openvgdb(games, b.openvgdb_index(self.conn))
        self.assertNotIn("synopsis", games[0])

    def test_an_unknown_serial_fills_nothing(self):
        games = self.disc(name="Bond (USA)", crc="DEADBEEF", serial="SLES-00001")
        b.enrich_from_openvgdb(games, *self.indexes())
        self.assertNotIn("synopsis", games[0])


class BuildPackTest(unittest.TestCase):
    def test_assembles_the_pack_document(self):
        pack = b.build_pack(
            system={"system": "Nintendo - Super Nintendo Entertainment System",
                    "group": "no-intro",
                    "thumbs": "Nintendo_-_Super_Nintendo_Entertainment_System",
                    "aliases": ["snes"]},
            dat_text=NO_INTRO_DAT,
            side_texts={"genre": GENRE_DAT, "serial": SERIAL_DAT},
            thumbs={},
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
            thumbs={},
            openvgdb={},
            built="2026-09-10",
        )
        by_id = {g["id"]: g for g in pack["games"]}
        vanguard = by_id["nintendo_super_nintendo_entertainment_system/crystal-vanguard"]
        self.assertEqual(vanguard["genre"], "Role-Playing")

    def test_missing_side_files_are_tolerated(self):
        pack = b.build_pack(
            system={"system": "Sony - PlayStation", "group": "redump",
                    "thumbs": "T", "aliases": []},
            dat_text=REDUMP_DAT,
            side_texts={},
            thumbs={},
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
