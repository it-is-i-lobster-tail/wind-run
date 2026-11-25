import Foundation

/// The same English activity names power picker search and automatic matching.
nonisolated struct WorkoutSymbolEntry: Identifiable {
    let id: String
    let title: String
    let terms: [String]
    let pickerOnlyTerms: [String]
    private let searchWords: Set<String>

    private static let aliases = [
        "figure.boxing": ["boxing", "punch", "jab", "knockout", "punches", "shadowboxing"],
        "figure.kickboxing": ["kickboxing"],
        "figure.jumprope": ["jump rope", "skipping"],
        "figure.dance": ["dance", "dancing", "groove"],
        "burst": ["blast", "bomb", "explode", "explosion", "explosive", "detonate", "boom"],
        "forward": ["accelerate", "fast forward", "speed up", "surge", "surges"],
        "arrow.up.forward": ["launch", "take off", "takeoff", "liftoff"],
        "tornado": ["tornado", "whirlwind", "twister"],
        "hurricane": ["hurricane", "cyclone", "storm chase", "storm chasing"],
        "fireworks": ["fireworks", "victory lap", "firework"],
        "speedometer": ["speedometer", "turbo", "pedal to the metal"],
        "scope": ["focus", "precision", "zero in"],
        "heart.badge.bolt": ["heart pounding", "pulse", "adrenaline", "pounding heart"],
        "timer": ["countdown", "timer", "beat the buzzer"],
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
        "workout.elephant": ["elephant", "elephants"],
        "workout.frog": ["frog", "frogs", "toad", "toads"],
        "workout.mouse": ["mouse", "mice"],
        "workout.goose": ["Goose", "geese", "gosling", "goslings"],
        "workout.snail": ["Snail", "snails", "sluggish"],
        "workout.pancakes": ["Pancakes"],
        "ant": ["ant", "ants", "ant march"],
        "bird": ["bird", "birds", "birdsong", "wings"],
        "cat": ["cat", "cats", "kitten", "kittens", "feline", "kitty", "kitties"],
        "dog": ["dog", "dogs", "pup", "puppy", "puppies", "hound", "doggo", "dog walk"],
        "fish": ["fish", "fishes", "salmon"],
        "hare": ["hare", "hares", "rabbits", "bunnies"],
        "ladybug": ["ladybug", "ladybird", "ladybugs", "ladybirds"],
        "lizard": ["lizard", "lizards", "gecko", "reptile", "geckos"],
        "pawprint": ["paw print", "paws", "pawprints", "paw", "paw prints"],
        "teddybear": ["teddy bear", "bear", "bears", "bear cub", "teddy", "grizzly"],
        "tortoise": ["tortoise", "tortoises", "turtles", "slow"],
        "figure.run": ["running", "jogging", "jog", "run"],
        "figure.walk": ["walking", "walk", "stroll"],
        "figure.hiking": ["hiking", "hike", "trail hike", "trek", "backpacking"],
        "figure.climbing": ["climbing", "rock climbing", "bouldering", "rock climb"],
        "figure.outdoor.cycle": ["cycling", "bike ride", "road bike", "mountain biking", "mountain bike", "biking", "bike", "ride"],
        "bicycle": ["bicycle"],
        "figure.indoor.cycle": ["indoor cycling", "stationary bike", "spin class", "spinning", "indoor bike"],
        "figure.run.treadmill": ["treadmill run", "treadmill"],
        "figure.track.and.field": ["track and field", "track meet"],
        "figure.highintensity.intervaltraining": ["HIIT", "high intensity interval training", "high intensity intervals"],
        "figure.strengthtraining.functional": ["functional strength", "functional training"],
        "dumbbell": ["weights", "lifting", "gym", "strength training", "weightlifting", "weight training"],
        "figure.cross.training": ["cross training", "crossfit", "crosstraining"],
        "figure.flexibility": ["flexibility", "stretching", "stretch", "mobility", "mobility work"],
        "figure.pool.swim": ["swimming", "swim", "pool laps", "butterfly stroke", "butterfly sets", "swim kick set", "kick set"],
        "figure.open.water.swim": ["open water swimming", "ocean swim", "lake swim", "sea swim"],
        "mountain.2": ["mountain", "mountains", "hills", "summit", "peak", "alpine"],
        "tree": ["forest", "woods", "woodland", "trail run"],
        "tent": ["camping", "camp", "campsite", "overnight hike"],
        "backpack": ["pack", "rucking", "ruck"],
        "map": ["route", "navigation", "orienteering"],
        "sunrise": ["sunrise", "dawn", "early morning"],
        "sunset": ["sunset", "dusk"],
        "waterbottle": ["water bottle", "hydration", "water break"],
        "waveform.path.ecg": ["heart rate", "cardio", "heart rate zone", "HR zone"],
        "flag.pattern.checkered": ["finish line", "race day", "finish chute"],
        "medal": ["personal best", "race medal", "PB", "PR", "personal record"],
        "shoeprints": ["footprints", "footsteps"],
        "leaf": ["cooldown"],
        "target": ["goal", "goal pace"],
        "metronome": ["cadence", "cadence work", "rhythm", "steps per minute"],
        "figure.yoga": ["yoga flow", "vinyasa", "sun salutation"],
        "binoculars": ["birdwatching", "bird watching", "wildlife watching"],
        "moon.stars": ["night", "nighttime", "moonlit"],
        "sun.max": ["sun", "sunny"],
        "cloud.rain": ["rainy", "drizzle", "downpour"],
        "wind": ["windy", "headwind", "tailwind"],
        "snowflake": ["snow", "snowy", "snowfall"],
        "water.waves": ["waves", "waterfront"],
        "party.popper": ["party popper", "celebrate", "party"],
        "face.smiling": ["smile", "happy", "joy"],
        "person.2": ["group run", "run club", "group hike"],
        "bubble.left.and.bubble.right": ["chat", "walk and talk"],
        "music.note": ["playlist", "tunes"],
        "sparkles": ["sparkle"],
        "cup.and.saucer": ["espresso", "latte"],
        "fork.knife": ["snack", "snacks"],
        "bolt": ["finishing kick"],
    ]

    private static let titles = [
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
        "run", "runs", "running", "jog", "jogging", "walk", "walking", "hike", "hiking",
        "ride", "bike", "biking", "cycling", "swim", "swimming", "repeat", "repeats", "interval", "intervals"
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

    static func bestMatch(_ words: [String]) -> String? {
        var activity: String?
        for length in stride(from: min(longest, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let term = words[start..<(start + length)].joined(separator: " ")
                guard let owner = index[term] else { continue }
                if !generic.contains(term) { return owner }
                if activity == nil { activity = owner }
            }
        }
        return activity
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
