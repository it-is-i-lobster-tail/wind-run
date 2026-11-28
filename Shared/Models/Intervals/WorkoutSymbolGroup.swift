// Public SF Symbol identifiers, selected from Apple's fitness, nature and weather
// categories and related families available on both iOS 26 and watchOS 26.
import Foundation

nonisolated struct WorkoutSymbolGroup: Identifiable {
    let title: String
    let symbols: [String]
    let namedChoices: [(id: String, name: String)]
    var id: String { title }

    private init(_ title: String, _ names: String) {
        self.title = title
        namedChoices = []
        symbols = names.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    init(_ title: String, choices: [(id: String, name: String)]) {
        self.title = title
        symbols = choices.map(\.id)
        namedChoices = choices
    }

    static let all = [
        Self("Run, Ride & Hike", """
            figure.run figure.walk figure.hiking figure.climbing figure.track.and.field
            figure.run.treadmill bicycle figure.outdoor.cycle figure.indoor.cycle
            mountain.2.fill road.lanes shoeprints.fill workout.stroller workout.train
            """),
        Self("Training & Recovery", """
            flame.fill bolt.fill repeat leaf.fill target stopwatch metronome heart.fill
            waveform.path.ecg dumbbell figure.strengthtraining.functional figure.highintensity.intervaltraining
            figure.yoga figure.flexibility figure.pool.swim figure.open.water.swim figure.cross.training
            flag.pattern.checkered medal brain waterbottle workout.nap
            """),
        Self("Trails & Outdoors", """
            tree.fill map backpack tent binoculars sunrise.fill sunset.fill moon.stars.fill
            sun.max cloud.rain wind snowflake water.waves workout.mist
            """),
        Self("Fun & Social", """
            party.popper.fill face.smiling.fill person.2.fill bubble.left.and.bubble.right.fill
            music.note sparkles figure.play cup.and.saucer.fill fork.knife workout.pancakes workout.vacation workout.library workout.dentist
            """),
        Self("Action", """
            burst.fill forward.fill arrow.up.forward tornado hurricane fireworks speedometer
            scope heart.badge.bolt timer figure.boxing figure.kickboxing figure.jumprope figure.dance
            """),
        Self("Animals", """
            workout.cheetah hare.fill tortoise.fill pawprint.fill dog cat bird fish lizard ant ladybug teddybear
            workout.goose workout.snail workout.fox workout.wolf workout.owl workout.duck
            workout.chicken workout.cow workout.pig workout.horse workout.sheep workout.deer
            workout.butterfly workout.bee workout.lion workout.elephant workout.frog workout.mouse workout.beaver
            """),
    ] + namedGroups
}
