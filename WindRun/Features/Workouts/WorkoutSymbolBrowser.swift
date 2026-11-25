import Foundation

/// The same English activity names power picker search and automatic matching.
nonisolated struct WorkoutSymbolEntry: Identifiable {
    let id: String
    let title: String
    let terms: [String]
    let searchText: String

    private static let aliases = [
        "figure.boxing": ["boxing", "punch", "jab", "knockout", "punches"],
        "figure.kickboxing": ["kickboxing", "kick", "kicks"],
        "figure.jumprope": ["jump rope", "jump", "jumps", "skipping"],
        "figure.dance": ["dance", "dancing", "groove"],
        "burst": ["blast", "bomb", "explode", "explosion", "explosive", "detonate", "boom"],
        "forward": ["accelerate", "fast forward", "speed up", "surge"],
        "arrow.up.forward": ["launch", "take off", "takeoff", "liftoff"],
        "tornado": ["tornado", "whirlwind", "twister"],
        "hurricane": ["hurricane", "cyclone", "storm chase"],
        "fireworks": ["fireworks", "victory lap"],
        "speedometer": ["speedometer", "turbo", "pedal to the metal"],
        "scope": ["focus", "precision", "zero in"],
        "heart.badge.bolt": ["heart pounding", "pulse", "adrenaline"],
        "timer": ["countdown", "timer", "beat the buzzer"],
        "workout.fox": ["fox", "foxes", "vixen"],
        "workout.wolf": ["wolf", "wolves", "wolfpack"],
        "workout.owl": ["owl", "owls"],
        "workout.duck": ["duck", "ducks", "duckling"],
        "workout.chicken": ["chicken", "chickens", "rooster", "hen"],
        "workout.cow": ["cow", "cows", "cattle"],
        "workout.pig": ["pig", "pigs", "piglet"],
        "workout.horse": ["horse", "horses", "pony", "stallion", "gallop"],
        "workout.sheep": ["sheep", "lamb", "ram", "ewe"],
        "workout.deer": ["deer", "stag", "fawn"],
        "workout.butterfly": ["butterfly", "butterflies"],
        "workout.bee": ["bee", "bees", "honeybee", "bumblebee"],
        "workout.lion": ["lion", "lions", "lioness"],
        "workout.elephant": ["elephant", "elephants"],
        "workout.frog": ["frog", "frogs", "toad"],
        "workout.mouse": ["mouse", "mice"],
        "workout.goose": ["Goose"],
        "workout.snail": ["Snail"],
        "workout.pancakes": ["Pancakes"],
        "ant": ["ant", "ants", "ant march"],
        "bird": ["bird", "birds", "birdsong", "wings"],
        "cat": ["cat", "cats", "kitten", "kittens", "feline"],
        "dog": ["dog", "dogs", "pup", "puppy", "puppies", "hound"],
        "fish": ["fish", "fishes", "salmon"],
        "hare": ["hare", "hares", "rabbits", "bunnies"],
        "ladybug": ["ladybug", "ladybird", "ladybugs"],
        "lizard": ["lizard", "lizards", "gecko", "reptile"],
        "pawprint": ["paw print", "paws", "pawprints"],
        "teddybear": ["teddy bear", "bear", "bears", "bear cub"],
        "tortoise": ["tortoise", "tortoises", "turtles"],
        "figure.run": ["running", "jogging", "jog", "run"],
        "figure.walk": ["walking", "walk", "stroll"],
        "figure.hiking": ["hiking", "hike", "trail hike", "trek", "backpacking"],
        "figure.climbing": ["climbing", "rock climbing", "bouldering"],
        "figure.outdoor.cycle": ["cycling", "bike ride", "road bike", "mountain biking", "mountain bike", "biking", "bike", "ride"],
        "bicycle": ["bicycle", "bike", "cycling"],
        "figure.indoor.cycle": ["indoor cycling", "stationary bike", "spin class", "spinning"],
        "figure.run.treadmill": ["treadmill run", "treadmill"],
        "figure.track.and.field": ["track and field", "track meet"],
        "figure.highintensity.intervaltraining": ["HIIT", "high intensity interval training"],
        "figure.strengthtraining.functional": ["functional strength", "functional training"],
        "dumbbell": ["weights", "lifting", "gym", "strength training", "weightlifting"],
        "figure.cross.training": ["cross training", "crossfit"],
        "figure.flexibility": ["flexibility", "stretching"],
        "figure.pool.swim": ["swimming", "swim", "pool laps"],
        "figure.open.water.swim": ["open water swimming", "ocean swim"],
        "mountain.2": ["mountain", "mountains", "hills", "summit", "peak", "alpine"],
        "tree": ["forest", "woods", "woodland", "trail run"],
        "tent": ["camping", "camp", "campsite"],
        "backpack": ["pack", "rucking", "ruck"],
        "map": ["route", "navigation", "orienteering"],
        "sunrise": ["sunrise", "dawn", "early morning"],
        "sunset": ["sunset", "dusk"],
        "waterbottle": ["water bottle", "hydration"],
        "waveform.path.ecg": ["heart rate", "cardio"],
        "flag.pattern.checkered": ["finish line", "race day"],
        "medal": ["personal best", "race medal"],
    ]

    private static let titles = [
        "party.popper": "Celebration", "face.smiling": "Smiles", "person.2": "Group",
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
        title = Self.titles[family] ?? (aliases.first ?? base).capitalized
        terms = ([base] + aliases).map { $0.lowercased() }
        let quickPick = WorkoutSymbol.catalog.first { $0.id == id }
        var keywords = (quickPick?.phrases ?? []) + [quickPick?.title ?? ""]
        if animal { keywords += ["animal", "animals", "wildlife"] }
        let names = [id, title] + terms + keywords + (WorkoutNickname.phrases[id] ?? [])
        searchText = WorkoutNickname.words(names.joined(separator: " ")).joined(separator: " ")
    }

    static let sections = WorkoutSymbolGroup.all.map { group in
        (title: group.title, entries: group.symbols.map { Self(id: $0, animal: group.title == "Animals") })
    }

    static func search(_ text: String) -> [(title: String, entries: [Self])] {
        let input = WorkoutIconQuery(text)
        let words = WorkoutNickname.words(input.text)
        let emoji = input.emojiNames.map { name in
            (words: WorkoutNickname.words(name), symbol: WorkoutIconMatcher.match(name) { _, _ in .infinity })
        }
        return sections.compactMap { section in
            let entries = section.entries.filter { entry in
                let text = entry.searchText + " " + section.title.lowercased()
                guard words.allSatisfy({ text.contains($0) }) else { return false }
                return emoji.isEmpty || emoji.contains { hint in
                    (hint.symbol != WorkoutIcon.fallback && hint.symbol == entry.id) ||
                    hint.words.allSatisfy { text.contains($0) }
                }
            }
            return entries.isEmpty ? nil : (section.title, entries)
        }
    }

    // Let a distinctive noun or action win over the activity in names such as “Fox Run”.
    private static let genericActivities: Set<String> = ["run", "running", "walk", "walking", "ride", "hike", "cycling", "bike"]

    static let nameMatches: [(term: String, id: String)] = sections.flatMap(\.entries)
        .flatMap { entry in entry.terms.map { (term: $0, id: entry.id) } }
        .filter { $0.term.count >= 3 }
        .sorted {
            let lhsGeneric = genericActivities.contains($0.term)
            let rhsGeneric = genericActivities.contains($1.term)
            if lhsGeneric != rhsGeneric { return !lhsGeneric }
            if $0.term.count != $1.term.count { return $0.term.count > $1.term.count }
            return $0.id < $1.id
        }
}
