import unittest

from followup import count_slice, outcomes


class RecoveryTests(unittest.TestCase):
    def test_nonempty_wrong_result_isnt_an_exact_recovery(self):
        questions = {"q": {"id": "q", "family": "f", "category": "list", "text": "runs",
                           "conversational": True, "boundary": False, "exclusion": False}}
        gold = {"q": {"action": "results", "ids": ["a"], "acceptedTopIDs": [], "ordered": False,
                      "slots": {"sport": "running"}, "constraints": [{"slot": "sport", "allowedIDs": ["a"]}]}}
        raw = {"queryID": "q", "lane": "rules", "action": "empty", "ids": [], "slots": {}, "status": "rules",
               "additionalTerms": [], "placeChoices": [], "repeatIndex": 0, "modelAttempted": False,
               "localMs": 0, "finalMs": 0}
        prior, = outcomes([raw], questions, gold, {}, "priorRules")
        changed = outcomes([{**raw, "action": "results", "ids": ["B"]}], questions, gold, {}, "revisedRules")
        result = count_slice(changed, {"q": prior})
        self.assertEqual(result["priorWrongEmptyNowNonempty"], 1)
        self.assertEqual(result["priorWrongEmptyNowExact"], 0)
        self.assertEqual(result["rowsViolatingExplicitPredicates"], 1)


if __name__ == "__main__":
    unittest.main()
