import unittest

import build_metadata_pack as builder
import packs_local


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self.names = packs_local.names_to_ids()

    def test_the_aliases_people_type_resolve(self):
        # None of these appears inside its own pack id, so they are the cases
        # that matching on the id alone silently rejects.
        self.assertEqual(packs_local.resolve("snes", self.names),
                         "nintendo_super_nintendo_entertainment_system")
        self.assertEqual(packs_local.resolve("ps1", self.names),
                         "sony_playstation")
        self.assertEqual(packs_local.resolve("psx", self.names),
                         "sony_playstation")
        self.assertEqual(packs_local.resolve("n64", self.names),
                         "nintendo_nintendo_64")

    def test_a_full_pack_id_resolves_to_itself(self):
        for pack_id in packs_local.pack_ids():
            self.assertEqual(packs_local.resolve(pack_id, self.names), pack_id)

    def test_an_exact_alias_beats_a_substring_of_another_pack(self):
        self.assertEqual(packs_local.resolve("xbox", self.names),
                         "microsoft_xbox")
        self.assertEqual(packs_local.resolve("playstation", self.names),
                         "sony_playstation")

    def test_a_substring_reaching_one_pack_resolves(self):
        self.assertEqual(packs_local.resolve("coleco", self.names),
                         "coleco_colecovision")

    def test_a_substring_reaching_several_packs_is_refused(self):
        with self.assertRaises(SystemExit) as raised:
            packs_local.resolve("nintendo", self.names)
        self.assertIn("ambiguous", str(raised.exception))

    def test_an_unknown_name_is_refused(self):
        with self.assertRaises(SystemExit) as raised:
            packs_local.resolve("dendy", self.names)
        self.assertIn("no pack matches", str(raised.exception))

    def test_every_alias_the_index_publishes_resolves(self):
        # The index ships these same aliases to the app, so a name the app can
        # see and this script cannot resolve would be a split between the two.
        for system in builder.SYSTEMS:
            pack_id = builder.normalize(system["system"])
            for alias in system["aliases"]:
                self.assertEqual(packs_local.resolve(alias, self.names),
                                 pack_id, alias)

    def test_the_default_argument_resolves(self):
        # Running the script bare has to work: the defect that motivated this
        # file was the default itself failing to resolve.
        for alias in packs_local.DEFAULT_SYSTEM:
            packs_local.resolve(alias, self.names)


if __name__ == "__main__":
    unittest.main()
