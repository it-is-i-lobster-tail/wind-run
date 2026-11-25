import Foundation

/// The same English activity names power picker search and automatic matching.
nonisolated struct WorkoutSymbolEntry: Identifiable {
    let id: String
    let title: String
    let terms: [String]
    let pickerOnlyTerms: [String]
    private let searchWords: Set<String>

    private static let aliases = [
        "workout.stroller": ["stroller", "strollers", "jogging stroller", "pram", "pushchair"],
        "workout.vacation": ["vacation", "holiday trip", "on holiday"],
        "workout.beaver": ["beaver", "beavers"],
        "workout.mist": ["mist", "misty", "fog", "foggy"],
        "workout.library": ["library", "book", "books", "library return"],
        "workout.nap": ["nap", "naps", "napping", "after nap"],
        "workout.dentist": ["dentist", "dental", "tooth", "teeth"],
        "workout.train": ["train", "train station", "railway", "railroad", "commuter train", "train ride"],
        "heart": ["cardiovascular", "legs and lungs"],
        "figure.boxing": ["boxing", "punch", "jab", "knockout", "punches", "shadowboxing"],
        "figure.kickboxing": ["kickboxing"],
        "figure.jumprope": ["jump rope", "skipping"],
        "figure.dance": ["dance", "dancing", "groove"],
        "burst": ["blast", "bomb", "explode", "explosion", "explosive", "detonate", "boom"],
        "forward": ["accelerate", "fast forward", "speed up", "surge", "surges", "progression", "progressive", "cutdown", "cutdowns", "negative split", "negative splits", "faster each mile", "strong finish", "finish strong", "last mile strong", "brisk finish", "pick up", "pickup", "last mile pickup"],
        "arrow.up.forward": ["launch", "take off", "takeoff", "liftoff", "comeback run", "return to running"],
        "tornado": ["tornado", "whirlwind", "twister"],
        "hurricane": ["hurricane", "cyclone", "storm chase", "storm chasing"],
        "fireworks": ["fireworks", "victory lap", "firework"],
        "speedometer": ["speedometer", "turbo", "pedal to the metal", "gears"],
        "scope": ["focus", "precision", "zero in"],
        "heart.badge.bolt": ["heart pounding", "pulse", "adrenaline", "pounding heart"],
        "timer": ["countdown", "timer", "beat the buzzer", "before pickup", "before school pickup"],
        "workout.cheetah": ["cheetah", "cheetahs", "cheta", "fast", "fastest", "speedy", "quick", "big cat", "leopard", "leopards"],
        "workout.fox": ["fox", "foxes", "vixen"],
        "workout.wolf": ["wolf", "wolves", "wolfpack", "wolf pack"],
        "workout.owl": ["owl", "owls"],
        "workout.duck": ["duck", "ducks", "duckling", "ducklings"],
        "workout.chicken": ["chicken", "chickens", "rooster", "hen", "roosters", "hens"],
        "workout.cow": ["cow", "cows", "cattle", "bull", "bulls"],
        "workout.pig": ["pig", "pigs", "piglet", "piglets"],
        "workout.horse": ["horse", "horses", "pony", "stallion", "gallop", "ponies", "galloping"],
        "workout.sheep": ["sheep", "lamb", "ram", "ewe", "lambs", "rams"],
        "workout.deer": ["deer", "stag", "fawn", "doe", "buck"],
        "workout.butterfly": ["butterfly", "butterflies"],
        "workout.bee": ["bee", "bees", "honeybee", "bumblebee", "bumblebees", "honeybees"],
        "workout.lion": ["lion", "lions", "lioness", "lionesses"],
        "workout.elephant": ["elephant", "elephants", "big", "huge"],
        "workout.frog": ["frog", "frogs", "toad", "toads"],
        "workout.mouse": ["mouse", "mice"],
        "workout.goose": ["Goose", "geese", "gosling", "goslings"],
        "workout.snail": ["Snail", "snails", "sluggish"],
        "workout.pancakes": ["Pancakes"],
        "ant": ["ant", "ants", "ant march"],
        "bird": ["bird", "birds", "birdsong", "wings"],
        "cat": ["cat", "cats", "kitten", "kittens", "feline", "kitty", "kitties"],
        "dog": ["dog", "dogs", "pup", "puppy", "puppies", "hound", "doggo", "dog walk", "with the dog"],
        "fish": ["fish", "fishes", "salmon"],
        "hare": ["hare", "hares", "rabbits", "bunnies"],
        "ladybug": ["ladybug", "ladybird", "ladybugs", "ladybirds"],
        "lizard": ["lizard", "lizards", "gecko", "reptile", "geckos"],
        "pawprint": ["paw print", "paws", "pawprints", "paw", "paw prints"],
        "teddybear": ["teddy bear", "bear", "bears", "bear cub", "teddy", "grizzly"],
        "tortoise": ["tortoise", "tortoises", "turtles", "slow", "slog"],
        "figure.run": ["running", "jogging", "jog", "run", "miles", "mile", "mileage"],
        "figure.walk": ["walking", "walk", "stroll", "walking breaks"],
        "figure.hiking": ["hiking", "hike", "trail hike", "trek", "backpacking"],
        "figure.climbing": ["climbing", "rock climbing", "bouldering", "rock climb"],
        "figure.outdoor.cycle": ["cycling", "bike ride", "road bike", "mountain biking", "mountain bike", "biking", "bike", "ride"],
        "bicycle": ["bicycle"],
        "figure.indoor.cycle": ["indoor cycling", "stationary bike", "spin class", "spinning", "indoor bike"],
        "figure.run.treadmill": ["treadmill run", "treadmill"],
        "figure.track.and.field": ["track and field", "track meet", "oval", "bell lap", "final lap", "back straight", "last lap", "laps", "track ladder", "relay", "xc", "spikes", "spike tune up", "track", "track lights", "200s", "600s", "800s", "1000s", "1200s", "1600s", "dual meet", "steeplechase", "michigan workout"],
        "figure.highintensity.intervaltraining": ["HIIT", "high intensity interval training", "high intensity intervals"],
        "figure.strengthtraining.functional": ["functional strength", "functional training"],
        "dumbbell": ["weights", "lifting", "gym", "strength training", "weightlifting", "weight training"],
        "figure.cross.training": ["cross training", "crossfit", "crosstraining", "brick jog", "brick run", "brick workout"],
        "figure.flexibility": ["flexibility", "stretching", "stretch", "mobility", "mobility work"],
        "figure.pool.swim": ["swimming", "swim", "pool laps", "butterfly stroke", "butterfly sets", "swim kick set", "kick set"],
        "figure.open.water.swim": ["open water swimming", "ocean swim", "lake swim", "sea swim"],
        "mountain.2": ["mountain", "mountains", "hills", "summit", "peak", "alpine", "downhill", "switchback", "switchbacks", "ridge", "hilly", "rolling roads", "stairs", "stadium steps", "hill repeats", "hill sprints", "hill reps"],
        "tree": ["forest", "woods", "woodland", "trail run", "trail", "trails", "trailhead", "grass", "park", "pines", "muddy", "dirt", "singletrack", "fire road", "bridle path", "gravel trail"],
        "tent": ["camping", "camp", "campsite", "overnight hike"],
        "backpack": ["pack", "rucking", "ruck"],
        "map": ["route", "navigation", "orienteering", "loop", "loops", "laps around", "scenic", "neighborhood", "neighbourhood", "bridge tour", "out back", "one mile back", "course preview", "new neighborhood", "school drop off", "bridge", "boardwalk", "circuit", "home from", "footbridge", "route home"],
        "sunrise": ["sunrise", "dawn", "early morning", "before breakfast", "first light", "morning", "breakfast run"],
        "sunset": ["sunset", "dusk", "last light", "blue hour", "after work"],
        "waterbottle": ["water bottle", "hydration", "water break", "aid station"],
        "waveform.path.ecg": ["heart rate", "cardio", "aerobic", "heart rate zone", "HR zone"],
        "flag.pattern.checkered": ["finish line", "race day", "race", "racing", "finish chute", "raceday", "5k", "10k", "15k", "five k", "ten k", "tuneup", "tune up", "course preview", "race course", "race meet", "dress rehearsal"],
        "medal": ["personal best", "race medal", "PB", "PR", "personal record"],
        "shoeprints": ["footprints", "footsteps", "new shoes", "footwork", "form practice", "drills"],
        "leaf": ["light", "light effort", "cooldown", "ez", "relaxed", "conversational", "shuffle", "taper", "warmup", "warm up", "wu", "cd", "reset", "recovery miles", "post race", "pre race shakeout", "shake off the cobwebs", "tired legs"],
        "target": ["goal", "goal pace", "pace practice", "pace sampler", "pace check", "test run", "practice run", "next lamppost", "at mp", "gmp", "half pace"],
        "metronome": ["cadence", "cadence work", "rhythm", "steady", "steady state", "steps per minute"],
        "figure.yoga": ["yoga flow", "vinyasa", "sun salutation"],
        "binoculars": ["birdwatching", "bird watching", "wildlife watching"],
        "moon.stars": ["night", "nighttime", "moonlit", "after dark", "in the dark", "pm miles", "porch light", "crescent moon", "headlamp", "head torch"],
        "sun.max": ["sun", "sunny", "solstice", "hot weather"],
        "cloud.rain": ["rainy", "drizzle", "downpour", "wet weather", "puddles", "showers"],
        "wind": ["windy", "headwind", "tailwind"],
        "snowflake": ["snow", "snowy", "snowfall"],
        "water.waves": ["waves", "waterfront", "lake", "river", "riverside", "canal", "creek", "reservoir", "bay", "shoreline"],
        "party.popper": ["party popper", "celebrate", "party", "birthday", "new year"],
        "face.smiling": ["smile", "happy", "joy"],
        "person.2": ["group run", "run club", "group hike", "social run", "social", "crew", "pack run", "with friends", "with a friend", "good company", "relay handoff", "with the club", "with dad", "with mom"],
        "bubble.left.and.bubble.right": ["chat", "walk and talk"],
        "music.note": ["playlist", "tunes", "headphones"],
        "sparkles": ["sparkle"],
        "cup.and.saucer": ["espresso", "latte"],
        "fork.knife": ["snack", "snacks", "bakery", "bagel", "bagels", "ice cream", "market", "donuts", "fuel practice", "fuel rehearsal", "fueling", "turkey", "brunch", "dinner", "takeout pickup", "takeout", "fuel test", "breakfast stop"],
        "bolt": ["finishing kick", "flybys", "flyby", "turnover", "leg speed", "start practice"],
        "road.lanes": ["base run", "base training", "mp blocks", "hm pace", "distance run", "miler", "medium long", "lr", "ten miler", "double digit miles", "long mileage"],
        "repeat": ["reps", "sets", "interval", "intervals", "ints", "blocks", "floats", "mile float", "mile on", "minute on", "minutes on", "seconds on", "on off", "run walk", "walk jog", "walk a minute", "lap", "mile repeats", "billat", "deek s quarters", "double run day", "quarters session"],
        "flame": ["cruise ints", "cruise interval", "critical speed"],
        "brain": ["mental break", "by feel", "no watch", "clear my head"],
        "stopwatch": ["time cap", "lunch break", "half hour"],
    ]

    private static let titles = [
        "heart": "Heart", "flame": "Flame", "repeat": "Repeat", "stopwatch": "Stopwatch", "brain": "Brain",
        "figure.track.and.field": "Track and field", "figure.outdoor.cycle": "Outdoor cycling",
        "backpack": "Backpack", "leaf": "Leaf", "target": "Target", "metronome": "Metronome",
        "figure.yoga": "Yoga", "binoculars": "Binoculars", "wind": "Wind", "snowflake": "Snowflake",
        "sparkles": "Sparkles", "bolt": "Bolt", "party.popper": "Celebration", "face.smiling": "Smiles", "person.2": "Group",
        "bubble.left.and.bubble.right": "Conversation", "music.note": "Music",
        "figure.play": "Play", "cup.and.saucer": "Coffee", "fork.knife": "Food",
        "moon.stars": "Night sky", "sun.max": "Sunshine", "cloud.rain": "Rain",
        "shoeprints": "Footprints", "mountain.2": "Mountains", "road.lanes": "Open road",
        "water.waves": "Water", "flag.pattern.checkered": "Finish line", "figure.run.treadmill": "Treadmill",
        "figure.highintensity.intervaltraining": "HIIT", "waterbottle": "Water bottle",
    ]

    init(id: String, animal: Bool = false) {
        self.id = id
        var components = id.components(separatedBy: ".")
        while let word = components.last, ["circle", "square", "fill"].contains(word) {
            components.removeLast()
        }
        let family = components.joined(separator: ".")
        let base = components.filter { $0 != "figure" }.joined(separator: " ")
        let aliases = Self.aliases[family] ?? []
        let label = aliases.first ?? base
        title = Self.titles[family] ?? (label.prefix(1).uppercased() + label.dropFirst())
        let quick = WorkoutSymbol.catalog.first { $0.id == id }
        let quickTerms = quick.map { [$0.title] + $0.phrases } ?? []
        let vocabulary = [title, base] + aliases + quickTerms + (WorkoutNickname.phrases[id] ?? [])
        terms = vocabulary.map { WorkoutNickname.words($0).joined(separator: " ") }
        let discovery = ["figure.jumprope": ["jump", "jumps"], "figure.kickboxing": ["kick", "kicks"],
                         "sunset": ["evening"]]
        pickerOnlyTerms = (discovery[family] ?? []) + (animal ? ["animal", "animals", "wildlife"] : [])
        searchWords = Set((terms + pickerOnlyTerms + [id]).flatMap(WorkoutNickname.words))
    }

    static let sections = WorkoutSymbolGroup.all.map { group in
        (title: group.title, entries: group.symbols.map { Self(id: $0, animal: group.title == "Animals") })
    }

    private static let generic: Set<String> = [
        "mile", "miles", "mileage", "5k", "10k", "15k", "run", "runs", "running", "jog", "jogging", "walk", "walking", "hike", "hiking",
        "lap", "ride", "bike", "biking", "cycling", "swim", "swimming", "repeat", "repeats", "interval", "intervals"
    ]

    // These identify context when there is no more descriptive workout cue.
    private static let context: Set<String> = [
        "big", "huge", "light",
        "sun", "neighborhood", "neighbourhood", "grass", "water", "steady", "lunch break", "by feel",
        "practice run", "loop", "loops", "laps", "mile", "miles", "mileage"
    ]

    private static let index: [String: String] = {
        let entries = sections.flatMap(\.entries)
        var owners: [String: String] = [:]
        for entry in entries {
            for term in entry.terms where owners[term] == nil { owners[term] = entry.id }
        }
        for entry in entries { owners[entry.title.lowercased()] = entry.id }
        return owners
    }()
    private static let longest = index.keys.map { $0.split(separator: " ").count }.max() ?? 1

    // Runners use the same rep notation for distance and time, e.g. 6x800 or six by three minutes.
    private static let counts: Set<String> = ["one", "two", "three", "four", "five", "six", "seven",
                                               "eight", "nine", "ten", "twelve", "twenty"]
    private static func describesRepetitions(_ words: [String]) -> Bool {
        func isCount(_ word: String) -> Bool { word.first?.isNumber == true || counts.contains(word) }
        for i in words.indices where i > 0 && i + 1 < words.count {
            if ["x", "by"].contains(words[i]), isCount(words[i - 1]) {
                let next = words[(i + 1)...].drop(while: { $0 == "a" || $0 == "an" })
                if let unit = next.first, isCount(unit) || ["½", "¼", "¾", "half", "quarter", "mile", "minute", "lap"].contains(unit) {
                    return true
                }
            }
            if words[i] == "on", words[(i + 1)...].contains("off"),
               isCount(words[i - 1]) || ["min", "minutes", "seconds"].contains(words[i - 1]) { return true }
        }
        return false
    }

    static func bestMatch(_ words: [String]) -> String? {
        var activity: String?
        var setting: String?
        for length in stride(from: min(longest, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let term = words[start..<(start + length)].joined(separator: " ")
                guard let owner = index[term] else { continue }
                if context.contains(term) && !generic.contains(term) {
                    if setting == nil { setting = owner }
                    continue
                }
                if !generic.contains(term) { return owner }
                if activity == nil { activity = owner }
            }
        }
        if describesRepetitions(words) { return "repeat" }
        if words.count == 2, ["saturday", "sunday"].contains(words[0]),
           let miles = Int(words[1]), (10...100).contains(miles) { return "road.lanes" }
        if let from = words.firstIndex(of: "from"), words.dropFirst(from + 2).contains("to") { return "map" }
        return setting ?? activity
    }

    static func search(_ text: String) -> [(title: String, entries: [Self])] {
        let words = WorkoutIconQuery(text).words
        guard !words.isEmpty else { return sections }
        let best = bestMatch(words)
        let distinctive = words.filter { !generic.contains($0) }
        let query = distinctive.isEmpty ? words : distinctive
        var results: [(title: String, entries: [Self])] = []
        for section in sections {
            let category = WorkoutNickname.words(section.title)
            let matchesCategory = words.allSatisfy { word in category.contains { $0.hasPrefix(word) } }
            var entries = section.entries.filter { entry in
                entry.id == best || matchesCategory || query.allSatisfy { word in
                    entry.searchWords.contains { $0.hasPrefix(word) }
                }
            }
            if let position = entries.firstIndex(where: { $0.id == best }) {
                let first = entries.remove(at: position)
                entries.insert(first, at: 0)
                results.insert((section.title, entries), at: 0)
            } else if !entries.isEmpty {
                results.append((section.title, entries))
            }
        }
        return results
    }
}
