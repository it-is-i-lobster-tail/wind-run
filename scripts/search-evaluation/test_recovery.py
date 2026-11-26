import unittest

from check_recovery import check


class RecoveryGateTests(unittest.TestCase):
    def test_correct_empty_result_cannot_mask_wrong_filter_or_leftover_term(self):
        query = {"id": "q", "text": "runs beyond five kilometers", "family": "f",
                 "category": "list", "conversational": True, "boundary": True, "exclusion": False}
        inputs = {"histories": [], "queries": [query]}
        gold = {"answers": [{"queryID": "q", "action": "empty", "ids": [], "acceptedTopIDs": [],
                             "slots": {"distance": "greater:5000"}, "constraints": []}]}
        row = {"queryID": "q", "lane": "rules", "repeatIndex": 0, "action": "empty", "ids": [],
               "slots": {"distance": ["greater:5000"]}, "additionalTerms": [], "placeChoices": [],
               "status": "rules", "modelAttempted": False, "localMs": 0, "finalMs": 0}
        self.assertEqual(check(inputs, gold, [row]), [])
        for change in ({"slots": {"distance": ["equal:5000"]}}, {"additionalTerms": ["beyond"]}):
            with self.subTest(change=change):
                self.assertEqual(check(inputs, gold, [{**row, **change}]), [query["text"]])
