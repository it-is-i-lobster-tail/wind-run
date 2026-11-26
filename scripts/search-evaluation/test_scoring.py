import unittest

from score import compare, score_row


class ScoringTests(unittest.TestCase):
    def setUp(self):
        self.q = dict(id="q", family="f", category="ranked", conversational=True, boundary=True, exclusion=False)
        self.gold = dict(action="results", ids=["a", "b"], acceptedTopIDs=["a", "b"], ordered=True,
                         slots={"distance": "greater:1609.344"}, constraints=[{"slot": "distance", "allowedIDs": ["a", "b"]}])
        self.raw = dict(lane="rules", action="results", ids=["B", "A"], slots={"distance": ["greater:1609.344000"], "sort": ["newest"]},
                        status="rules", modelAttempted=False, repeatIndex=0, localMs=0.1, finalMs=0.2,
                        additionalTerms=[], placeChoices=[])

    def test_tied_top_and_explicit_boundary(self):
        row = score_row(self.raw, self.q, self.gold, {})
        self.assertTrue(row["success"])
        self.assertEqual(row["droppedSlots"], [])
        self.raw["slots"] = {"distance": ["atLeast:1609.344"]}
        self.assertEqual(score_row(self.raw, self.q, self.gold, {})["droppedSlots"], ["distance"])

    def test_action_requires_all_place_choices(self):
        self.gold.update(action="clarify", placeChoices=["Portland, ME", "Portland, OR"])
        self.raw.update(action="clarify", ids=[], placeChoices=["Portland, OR"])
        self.assertFalse(score_row(self.raw, self.q, self.gold, {})["success"])

    def test_paired_bootstrap_keeps_queries_together(self):
        row = score_row(self.raw, self.q, self.gold, {})
        result = compare([{**row, "success": False}, {**row, "lane": "hybrid"}], "rules", "hybrid", True)
        self.assertEqual((result["wins"], result["gain"], result["ci95"]), (1, 1, [1, 1]))


if __name__ == "__main__":
    unittest.main()
