# Embedding distance calibration

History search reads a word nothing in the history has as a history word with the same meaning, using
Apple's on-device English word embedding (`WorkoutSearchMeanings`). `calibrate.swift` prints
`NLEmbedding.distance`, the gap between the two unit vectors (sqrt(2 · (1 − cos)), 0 to 2), which is the
scale the app compares against. It prints the distance for pairs that should join and pairs that must not, so the limit can be checked on a Mac:

```sh
swift scripts/search-evaluation/embedding-calibration/calibrate.swift
```

Measured 2026-11-26 (macOS, embedding revision 1, 57,171 words, 300 dimensions):

- Joined below the limit of 0.64: mountain/mountains 0.516, downpour/rain 0.614.
- Kept apart: knee/ankle 0.656, wife/husband 0.657, dog/cat 0.717, morning/evening 0.785,
  north/south 0.791, river/lake 0.858.
- Good pairs above the limit, so not joined: canine/dog 0.729, ache/pain 0.754, sunny/sunshine 0.847.

Neighbors and opposites sit as close as true synonyms, so the limit is kept tight. Curated synonyms stay in
`WorkoutSearchVocabulary.synonyms`; the embedding only covers what that table misses. Words outside the
embedding's vocabulary (most place names and some lowercase day names) have no vector and stay not understood.
