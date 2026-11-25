// Public SF Symbol identifiers, selected from Apple's fitness, nature and weather
// categories and related families available on both iOS 26 and watchOS 26.
import Foundation

nonisolated struct WorkoutSymbolGroup: Identifiable {
    let title: String
    let symbols: [String]
    var id: String { title }

    private init(_ title: String, _ names: String) {
        self.title = title
        symbols = names.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static let all = [
        Self("Fun & Social", """
            party.popper.fill face.smiling.fill person.2.fill bubble.left.and.bubble.right.fill music.note
            workout.goose workout.snail workout.pancakes
            """),
        Self("Run, Ride & Hike", """
            bicycle bicycle.circle bicycle.circle.fill
            bicycle.sensor.tag.radiowaves.left.and.right bicycle.sensor.tag.radiowaves.left.and.right.fill
            figure.climbing figure.climbing.circle figure.climbing.circle.fill
            figure.hand.cycling figure.hand.cycling.circle figure.hand.cycling.circle.fill
            figure.hiking figure.hiking.circle figure.hiking.circle.fill
            figure.indoor.cycle figure.indoor.cycle.circle figure.indoor.cycle.circle.fill
            figure.outdoor.cycle figure.outdoor.cycle.circle figure.outdoor.cycle.circle.fill
            figure.roll.runningpace figure.roll.runningpace.circle figure.roll.runningpace.circle.fill
            figure.run figure.run.circle figure.run.circle.fill
            figure.run.square.stack figure.run.square.stack.fill
            figure.run.treadmill figure.run.treadmill.circle figure.run.treadmill.circle.fill
            figure.track.and.field figure.track.and.field.circle figure.track.and.field.circle.fill
            figure.walk
            figure.walk.arrival
            figure.walk.circle figure.walk.circle.fill
            figure.walk.departure
            figure.walk.diamond figure.walk.diamond.fill
            figure.walk.motion
            figure.walk.motion.trianglebadge.exclamationmark
            figure.walk.suitcase.rolling figure.walk.suitcase.rolling.circle figure.walk.suitcase.rolling.circle.fill
            figure.walk.treadmill figure.walk.treadmill.circle figure.walk.treadmill.circle.fill
            figure.walk.triangle figure.walk.triangle.fill
            mountain.2 mountain.2.circle mountain.2.circle.fill mountain.2.fill
            road.lanes
            road.lanes.curved.left
            road.lanes.curved.right
            scooter
            shoe
            shoe.2 shoe.2.fill
            shoe.arrow.trianglehead.up.and.down shoe.arrow.trianglehead.up.and.down.fill
            shoe.arrow.trianglehead.up.right shoe.arrow.trianglehead.up.right.circle shoe.arrow.trianglehead.up.right.circle.fill shoe.arrow.trianglehead.up.right.fill
            shoe.circle shoe.circle.fill shoe.fill
            shoeprints.fill
            snowflake.road.lane
            snowflake.road.lane.dashed
            stairs
            wheelchair
            """),
        Self("Exercise & Sports", """
            1.lane
            10.lane
            11.lane
            12.lane
            2.lane
            3.lane
            4.lane
            5.lane
            6.lane
            7.lane
            8.lane
            9.lane
            american.football american.football.circle american.football.circle.fill american.football.fill
            american.football.professional american.football.professional.circle american.football.professional.circle.fill american.football.professional.fill
            australian.football australian.football.circle australian.football.circle.fill australian.football.fill
            baseball baseball.circle baseball.circle.fill
            baseball.diamond.bases
            baseball.diamond.bases.outs.indicator
            baseball.fill
            basketball basketball.circle basketball.circle.fill basketball.fill
            chevron.down.2
            chevron.down.forward.dotted.2
            chevron.down.right.dotted.2
            chevron.up.2
            chevron.up.forward.dotted.2
            chevron.up.right.dotted.2
            cricket.ball cricket.ball.circle cricket.ball.circle.fill cricket.ball.fill
            duffle.bag duffle.bag.fill
            dumbbell dumbbell.fill
            figure.american.football figure.american.football.circle figure.american.football.circle.fill
            figure.archery figure.archery.circle figure.archery.circle.fill
            figure.australian.football figure.australian.football.circle figure.australian.football.circle.fill
            figure.badminton figure.badminton.circle figure.badminton.circle.fill
            figure.barre figure.barre.circle figure.barre.circle.fill
            figure.baseball figure.baseball.circle figure.baseball.circle.fill
            figure.basketball figure.basketball.circle figure.basketball.circle.fill
            figure.bowling figure.bowling.circle figure.bowling.circle.fill
            figure.boxing figure.boxing.circle figure.boxing.circle.fill
            figure.cooldown figure.cooldown.circle figure.cooldown.circle.fill
            figure.core.training figure.core.training.circle figure.core.training.circle.fill
            figure.cricket figure.cricket.circle figure.cricket.circle.fill
            figure.cross.training figure.cross.training.circle figure.cross.training.circle.fill
            figure.curling figure.curling.circle figure.curling.circle.fill
            figure.dance figure.dance.circle figure.dance.circle.fill
            figure.disc.sports figure.disc.sports.circle figure.disc.sports.circle.fill
            figure.elliptical figure.elliptical.circle figure.elliptical.circle.fill
            figure.equestrian.sports figure.equestrian.sports.circle figure.equestrian.sports.circle.fill
            figure.fencing figure.fencing.circle figure.fencing.circle.fill
            figure.field.hockey figure.field.hockey.circle figure.field.hockey.circle.fill
            figure.fishing figure.fishing.circle figure.fishing.circle.fill
            figure.flexibility figure.flexibility.circle figure.flexibility.circle.fill
            figure.golf figure.golf.circle figure.golf.circle.fill
            figure.gymnastics figure.gymnastics.circle figure.gymnastics.circle.fill
            figure.handball figure.handball.circle figure.handball.circle.fill
            figure.highintensity.intervaltraining figure.highintensity.intervaltraining.circle figure.highintensity.intervaltraining.circle.fill
            figure.hockey figure.hockey.circle figure.hockey.circle.fill
            figure.hunting figure.hunting.circle figure.hunting.circle.fill
            figure.ice.hockey figure.ice.hockey.circle figure.ice.hockey.circle.fill
            figure.ice.skating figure.ice.skating.circle figure.ice.skating.circle.fill
            figure.indoor.rowing figure.indoor.rowing.circle figure.indoor.rowing.circle.fill
            figure.indoor.soccer figure.indoor.soccer.circle figure.indoor.soccer.circle.fill
            figure.jumprope figure.jumprope.circle figure.jumprope.circle.fill
            figure.kickboxing figure.kickboxing.circle figure.kickboxing.circle.fill
            figure.lacrosse figure.lacrosse.circle figure.lacrosse.circle.fill
            figure.martial.arts figure.martial.arts.circle figure.martial.arts.circle.fill
            figure.mind.and.body figure.mind.and.body.circle figure.mind.and.body.circle.fill
            figure.mixed.cardio figure.mixed.cardio.circle figure.mixed.cardio.circle.fill
            figure.open.water.swim figure.open.water.swim.circle figure.open.water.swim.circle.fill
            figure.outdoor.rowing figure.outdoor.rowing.circle figure.outdoor.rowing.circle.fill
            figure.outdoor.soccer figure.outdoor.soccer.circle figure.outdoor.soccer.circle.fill
            figure.pickleball figure.pickleball.circle figure.pickleball.circle.fill
            figure.pilates figure.pilates.circle figure.pilates.circle.fill
            figure.play figure.play.circle figure.play.circle.fill
            figure.pool.swim figure.pool.swim.circle figure.pool.swim.circle.fill
            figure.racquetball figure.racquetball.circle figure.racquetball.circle.fill
            figure.roll figure.roll.circle figure.roll.circle.fill
            figure.rolling figure.rolling.circle figure.rolling.circle.fill
            figure.rugby figure.rugby.circle figure.rugby.circle.fill
            figure.sailing figure.sailing.circle figure.sailing.circle.fill
            figure.seated.seatbelt
            figure.seated.seatbelt.and.airbag.off
            figure.seated.seatbelt.and.airbag.on
            figure.seated.seatbelt.left.drive.seats.1
            figure.seated.seatbelt.left.drive.seats.1.1 figure.seated.seatbelt.left.drive.seats.1.1.fill
            figure.seated.seatbelt.left.drive.seats.1.2 figure.seated.seatbelt.left.drive.seats.1.2.fill
            figure.seated.seatbelt.left.drive.seats.1.fill
            figure.seated.seatbelt.left.drive.seats.2
            figure.seated.seatbelt.left.drive.seats.2.2
            figure.seated.seatbelt.left.drive.seats.2.2.2 figure.seated.seatbelt.left.drive.seats.2.2.2.fill
            figure.seated.seatbelt.left.drive.seats.2.2.3 figure.seated.seatbelt.left.drive.seats.2.2.3.fill
            figure.seated.seatbelt.left.drive.seats.2.2.fill
            figure.seated.seatbelt.left.drive.seats.2.3
            figure.seated.seatbelt.left.drive.seats.2.3.2 figure.seated.seatbelt.left.drive.seats.2.3.2.fill
            figure.seated.seatbelt.left.drive.seats.2.3.3 figure.seated.seatbelt.left.drive.seats.2.3.3.fill
            figure.seated.seatbelt.left.drive.seats.2.3.fill
            figure.seated.seatbelt.left.drive.seats.2.fill
            figure.seated.seatbelt.left.drive.seats.3
            figure.seated.seatbelt.left.drive.seats.3.3
            figure.seated.seatbelt.left.drive.seats.3.3.3 figure.seated.seatbelt.left.drive.seats.3.3.3.fill
            figure.seated.seatbelt.left.drive.seats.3.3.fill
            figure.seated.seatbelt.left.drive.seats.3.fill
            figure.seated.side.left
            figure.seated.side.left.air.distribution.indirect
            figure.seated.side.left.air.distribution.lower
            figure.seated.side.left.air.distribution.lower.angled.and.upper.angled
            figure.seated.side.left.air.distribution.middle
            figure.seated.side.left.air.distribution.middle.and.lower
            figure.seated.side.left.air.distribution.middle.and.lower.angled
            figure.seated.side.left.air.distribution.upper
            figure.seated.side.left.air.distribution.upper.and.middle.and.lower
            figure.seated.side.left.air.distribution.upper.angled.and.dottedline.and.lower.angled
            figure.seated.side.left.air.distribution.upper.angled.and.lower.angled
            figure.seated.side.left.air.distribution.upper.angled.and.middle
            figure.seated.side.left.air.distribution.upper.angled.and.middle.and.lower.angled
            figure.seated.side.left.airbag.off
            figure.seated.side.left.airbag.off.2
            figure.seated.side.left.airbag.on
            figure.seated.side.left.airbag.on.2
            figure.seated.side.left.automatic
            figure.seated.side.left.fan
            figure.seated.side.left.steeringwheel
            figure.seated.side.left.windshield.front.and.heat.waves
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.lower
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.middle
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.middle.and.lower
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.upper
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.upper.and.lower
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.upper.and.middle
            figure.seated.side.left.windshield.front.and.heat.waves.air.distribution.upper.and.middle.and.lower
            figure.seated.side.right
            figure.seated.side.right.air.distribution.indirect
            figure.seated.side.right.air.distribution.lower
            figure.seated.side.right.air.distribution.lower.angled.and.upper.angled
            figure.seated.side.right.air.distribution.middle
            figure.seated.side.right.air.distribution.middle.and.lower
            figure.seated.side.right.air.distribution.middle.and.lower.angled
            figure.seated.side.right.air.distribution.upper
            figure.seated.side.right.air.distribution.upper.and.middle.and.lower
            figure.seated.side.right.air.distribution.upper.angled.and.dottedline.and.lower.angled
            figure.seated.side.right.air.distribution.upper.angled.and.lower.angled
            figure.seated.side.right.air.distribution.upper.angled.and.middle
            figure.seated.side.right.air.distribution.upper.angled.and.middle.and.lower.angled
            figure.seated.side.right.airbag.off
            figure.seated.side.right.airbag.off.2
            figure.seated.side.right.airbag.on
            figure.seated.side.right.airbag.on.2
            figure.seated.side.right.automatic
            figure.seated.side.right.child.lap
            figure.seated.side.right.fan
            figure.seated.side.right.steeringwheel
            figure.seated.side.right.windshield.front.and.heat.waves
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.lower
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.middle
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.middle.and.lower
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.upper
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.upper.and.lower
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.upper.and.middle
            figure.seated.side.right.windshield.front.and.heat.waves.air.distribution.upper.and.middle.and.lower
            figure.skateboarding figure.skateboarding.circle figure.skateboarding.circle.fill
            figure.skiing.crosscountry figure.skiing.crosscountry.circle figure.skiing.crosscountry.circle.fill
            figure.skiing.downhill figure.skiing.downhill.circle figure.skiing.downhill.circle.fill
            figure.snowboarding figure.snowboarding.circle figure.snowboarding.circle.fill
            figure.socialdance figure.socialdance.circle figure.socialdance.circle.fill
            figure.softball figure.softball.circle figure.softball.circle.fill
            figure.squash figure.squash.circle figure.squash.circle.fill
            figure.stair.stepper figure.stair.stepper.circle figure.stair.stepper.circle.fill
            figure.stairs figure.stairs.circle figure.stairs.circle.fill
            figure.step.training figure.step.training.circle figure.step.training.circle.fill
            figure.strengthtraining.functional figure.strengthtraining.functional.circle figure.strengthtraining.functional.circle.fill
            figure.strengthtraining.traditional figure.strengthtraining.traditional.circle figure.strengthtraining.traditional.circle.fill
            figure.surfing figure.surfing.circle figure.surfing.circle.fill
            figure.table.tennis figure.table.tennis.circle figure.table.tennis.circle.fill
            figure.taichi figure.taichi.circle figure.taichi.circle.fill
            figure.tennis figure.tennis.circle figure.tennis.circle.fill
            figure.volleyball figure.volleyball.circle figure.volleyball.circle.fill
            figure.water.fitness figure.water.fitness.circle figure.water.fitness.circle.fill
            figure.waterpolo figure.waterpolo.circle figure.waterpolo.circle.fill
            figure.wrestling figure.wrestling.circle figure.wrestling.circle.fill
            figure.yoga figure.yoga.circle figure.yoga.circle.fill
            flag.2.crossed flag.2.crossed.circle flag.2.crossed.circle.fill flag.2.crossed.fill
            flag.and.flag.filled.crossed
            flag.filled.and.flag.crossed
            flag.pattern.checkered
            flag.pattern.checkered.2.crossed
            flag.pattern.checkered.circle flag.pattern.checkered.circle.fill
            gamecontroller gamecontroller.circle gamecontroller.circle.fill gamecontroller.fill
            gauge.with.needle gauge.with.needle.fill
            hockey.puck hockey.puck.circle hockey.puck.circle.fill hockey.puck.fill
            lane
            medal medal.fill
            oar.2.crossed oar.2.crossed.circle oar.2.crossed.circle.fill
            rosette
            rugbyball rugbyball.circle rugbyball.circle.fill rugbyball.fill
            skateboard skateboard.fill
            skis skis.fill
            snowboard snowboard.fill
            soccerball soccerball.circle soccerball.circle.fill
            soccerball.circle.fill.inverse
            soccerball.circle.inverse
            soccerball.inverse
            sportscourt sportscourt.circle sportscourt.circle.fill sportscourt.fill
            surfboard surfboard.fill
            target
            tennis.racket tennis.racket.circle tennis.racket.circle.fill
            tennisball tennisball.circle tennisball.circle.fill tennisball.fill
            trophy trophy.circle trophy.circle.fill trophy.fill
            volleyball volleyball.circle volleyball.circle.fill volleyball.fill
            water.waves
            water.waves.and.arrow.trianglehead.down
            water.waves.and.arrow.trianglehead.down.trianglebadge.exclamationmark
            water.waves.and.arrow.trianglehead.up
            water.waves.slash
            """),
        Self("Gear, Routes & Camping", """
            backpack backpack.circle backpack.circle.fill backpack.fill
            backpack.sensor.tag.radiowaves.left.and.right backpack.sensor.tag.radiowaves.left.and.right.fill
            beach.umbrella beach.umbrella.fill
            binoculars binoculars.circle binoculars.circle.fill binoculars.fill
            compass.drawing
            ferry ferry.fill
            flag
            flag.badge.ellipsis flag.badge.ellipsis.fill
            flag.circle flag.circle.fill flag.fill
            flag.pattern.checkered.lc
            flag.slash flag.slash.circle flag.slash.circle.fill flag.slash.fill
            flag.square flag.square.fill
            flashlight.off.circle flashlight.off.circle.fill flashlight.off.fill
            flashlight.on.circle flashlight.on.circle.fill flashlight.on.fill
            flashlight.slash flashlight.slash.circle flashlight.slash.circle.fill
            globe
            globe.americas globe.americas.fill
            globe.asia.australia globe.asia.australia.fill
            globe.badge.chevron.backward
            globe.badge.clock globe.badge.clock.fill
            globe.central.south.asia globe.central.south.asia.fill
            globe.desk globe.desk.fill
            globe.europe.africa globe.europe.africa.fill
            globe.fill
            helmet helmet.fill
            lifepreserver lifepreserver.fill
            location.north location.north.circle location.north.circle.fill location.north.fill
            location.north.line location.north.line.fill
            map map.circle map.circle.fill map.fill
            mappin
            mappin.and.ellipse mappin.and.ellipse.circle mappin.and.ellipse.circle.fill
            mappin.circle mappin.circle.fill
            mappin.slash mappin.slash.circle mappin.slash.circle.fill
            mappin.square mappin.square.fill
            point.bottomleft.filled.forward.to.point.topright.scurvepath
            point.bottomleft.forward.to.arrow.triangle.scurvepath point.bottomleft.forward.to.arrow.triangle.scurvepath.fill
            point.bottomleft.forward.to.arrow.triangle.uturn.scurvepath point.bottomleft.forward.to.arrow.triangle.uturn.scurvepath.fill
            point.bottomleft.forward.to.point.topright.filled.scurvepath
            point.bottomleft.forward.to.point.topright.scurvepath point.bottomleft.forward.to.point.topright.scurvepath.fill
            point.forward.to.point.capsulepath point.forward.to.point.capsulepath.fill
            point.topleft.down.to.point.bottomright.curvepath point.topleft.down.to.point.bottomright.curvepath.fill
            point.topleft.down.to.point.bottomright.filled.curvepath
            point.topleft.filled.down.to.point.bottomright.curvepath
            point.topright.arrow.triangle.backward.to.point.bottomleft.filled.scurvepath
            point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath.fill
            point.topright.filled.arrow.triangle.backward.to.point.bottomleft.scurvepath
            sailboat sailboat.circle sailboat.circle.fill sailboat.fill
            signpost.and.arrowtriangle.up signpost.and.arrowtriangle.up.circle signpost.and.arrowtriangle.up.circle.fill signpost.and.arrowtriangle.up.fill
            signpost.left signpost.left.circle signpost.left.circle.fill signpost.left.fill
            signpost.right
            signpost.right.and.left signpost.right.and.left.circle signpost.right.and.left.circle.fill signpost.right.and.left.fill
            signpost.right.circle signpost.right.circle.fill signpost.right.fill
            sunglasses sunglasses.fill
            tent
            tent.2 tent.2.circle tent.2.circle.fill tent.2.fill
            tent.circle tent.circle.fill tent.fill
            umbrella umbrella.circle umbrella.circle.fill umbrella.fill
            umbrella.gauge.open
            umbrella.percent umbrella.percent.fill
            umbrella.sensor.tag.radiowaves.left.and.right umbrella.sensor.tag.radiowaves.left.and.right.fill
            waterbottle waterbottle.fill
            """),
        Self("Weather & Sky", """
            aqi.high
            aqi.low
            aqi.medium
            carbon.dioxide.cloud carbon.dioxide.cloud.fill
            carbon.monoxide.cloud carbon.monoxide.cloud.fill
            cloud
            cloud.bolt cloud.bolt.circle cloud.bolt.circle.fill cloud.bolt.fill
            cloud.bolt.rain cloud.bolt.rain.circle cloud.bolt.rain.circle.fill cloud.bolt.rain.fill
            cloud.circle cloud.circle.fill
            cloud.drizzle cloud.drizzle.circle cloud.drizzle.circle.fill cloud.drizzle.fill
            cloud.fill
            cloud.fog cloud.fog.circle cloud.fog.circle.fill cloud.fog.fill
            cloud.hail cloud.hail.circle cloud.hail.circle.fill cloud.hail.fill
            cloud.heavyrain cloud.heavyrain.circle cloud.heavyrain.circle.fill cloud.heavyrain.fill
            cloud.moon
            cloud.moon.bolt cloud.moon.bolt.circle cloud.moon.bolt.circle.fill cloud.moon.bolt.fill
            cloud.moon.circle cloud.moon.circle.fill cloud.moon.fill
            cloud.moon.rain cloud.moon.rain.circle cloud.moon.rain.circle.fill cloud.moon.rain.fill
            cloud.rain cloud.rain.circle cloud.rain.circle.fill cloud.rain.fill
            cloud.rainbow.crop cloud.rainbow.crop.fill
            cloud.sleet cloud.sleet.circle cloud.sleet.circle.fill cloud.sleet.fill
            cloud.snow cloud.snow.circle cloud.snow.circle.fill cloud.snow.fill
            cloud.sun
            cloud.sun.bolt cloud.sun.bolt.circle cloud.sun.bolt.circle.fill cloud.sun.bolt.fill
            cloud.sun.circle cloud.sun.circle.fill cloud.sun.fill
            cloud.sun.rain cloud.sun.rain.circle cloud.sun.rain.circle.fill cloud.sun.rain.fill
            degreesign.celsius
            degreesign.fahrenheit
            humidity humidity.fill
            hurricane hurricane.circle hurricane.circle.fill
            moon moon.circle moon.circle.fill
            moon.dust moon.dust.circle moon.dust.circle.fill moon.dust.fill
            moon.fill
            moon.haze moon.haze.circle moon.haze.circle.fill moon.haze.fill
            moon.stars moon.stars.circle moon.stars.circle.fill moon.stars.fill
            rainbow
            smoke smoke.circle smoke.circle.fill smoke.fill
            snowflake snowflake.circle snowflake.circle.fill
            snowflake.slash
            sparkles
            sun.dust sun.dust.circle sun.dust.circle.fill sun.dust.fill
            sun.haze sun.haze.circle sun.haze.circle.fill sun.haze.fill
            sun.horizon sun.horizon.circle sun.horizon.circle.fill sun.horizon.fill
            sun.max sun.max.circle sun.max.circle.fill sun.max.fill
            sun.max.trianglebadge.exclamationmark sun.max.trianglebadge.exclamationmark.fill
            sun.min sun.min.fill
            sun.rain sun.rain.circle sun.rain.circle.fill sun.rain.fill
            sun.snow sun.snow.circle sun.snow.circle.fill sun.snow.fill
            sunrise sunrise.circle sunrise.circle.fill sunrise.fill
            sunset sunset.circle sunset.circle.fill sunset.fill
            thermometer.high
            thermometer.low
            thermometer.medium
            thermometer.medium.slash
            thermometer.snowflake thermometer.snowflake.circle thermometer.snowflake.circle.fill
            thermometer.sun thermometer.sun.circle thermometer.sun.circle.fill thermometer.sun.fill
            thermometer.variable
            thermometer.variable.and.figure thermometer.variable.and.figure.circle thermometer.variable.and.figure.circle.fill
            thermometer.variable.badge.clock
            thermometer.variable.badge.play
            tornado tornado.circle tornado.circle.fill
            tropicalstorm tropicalstorm.circle tropicalstorm.circle.fill
            wind wind.circle wind.circle.fill
            wind.snow wind.snow.circle wind.snow.circle.fill
            """),
        Self("Nature & Wildlife", """
            allergens allergens.fill
            ant ant.circle ant.circle.fill ant.fill
            apple.meditate apple.meditate.circle apple.meditate.circle.fill
            apple.meditate.square.stack apple.meditate.square.stack.fill
            atom
            bird bird.circle bird.circle.fill bird.fill
            bolt
            bolt.badge.automatic bolt.badge.automatic.fill
            bolt.badge.checkmark bolt.badge.checkmark.fill
            bolt.badge.clock bolt.badge.clock.fill
            bolt.badge.xmark bolt.badge.xmark.fill
            bolt.circle bolt.circle.fill bolt.fill
            bolt.shield bolt.shield.fill
            bolt.slash bolt.slash.circle bolt.slash.circle.fill bolt.slash.fill
            bolt.square bolt.square.fill
            bolt.trianglebadge.exclamationmark bolt.trianglebadge.exclamationmark.fill
            camera.macro camera.macro.circle camera.macro.circle.fill
            camera.macro.slash camera.macro.slash.circle camera.macro.slash.circle.fill
            carrot carrot.fill
            cat cat.circle cat.circle.fill cat.fill
            dog dog.circle dog.circle.fill dog.fill
            drop drop.circle drop.circle.fill
            drop.degreesign drop.degreesign.fill
            drop.degreesign.slash drop.degreesign.slash.fill
            drop.fill
            drop.halffull
            drop.keypad.rectangle drop.keypad.rectangle.fill
            drop.transmission
            drop.triangle drop.triangle.fill
            environments environments.circle environments.circle.fill environments.fill
            environments.slash environments.slash.circle environments.slash.circle.fill environments.slash.fill
            fish fish.circle fish.circle.fill fish.fill
            flame flame.circle flame.circle.fill flame.fill
            fossil.shell fossil.shell.fill
            hare hare.circle hare.circle.fill hare.fill
            ladybug ladybug.circle ladybug.circle.fill ladybug.fill
            ladybug.slash ladybug.slash.circle ladybug.slash.circle.fill ladybug.slash.fill
            laurel.leading
            laurel.trailing
            leaf
            leaf.arrow.trianglehead.clockwise
            leaf.circle leaf.circle.fill leaf.fill
            lizard lizard.circle lizard.circle.fill lizard.fill
            microbe microbe.circle microbe.circle.fill microbe.fill
            moonphase.first.quarter
            moonphase.first.quarter.inverse
            moonphase.full.moon
            moonphase.full.moon.inverse
            moonphase.last.quarter
            moonphase.last.quarter.inverse
            moonphase.new.moon
            moonphase.new.moon.inverse
            moonphase.waning.crescent
            moonphase.waning.crescent.inverse
            moonphase.waning.gibbous
            moonphase.waning.gibbous.inverse
            moonphase.waxing.crescent
            moonphase.waxing.crescent.inverse
            moonphase.waxing.gibbous
            moonphase.waxing.gibbous.inverse
            pawprint pawprint.circle pawprint.circle.fill pawprint.fill
            service.dog service.dog.fill
            teddybear teddybear.fill
            tortoise tortoise.circle tortoise.circle.fill tortoise.fill
            tree tree.circle tree.circle.fill tree.fill
            """),
        Self("Training, Fuel & Recovery", """
            alarm alarm.fill
            alarm.waves.left.and.right alarm.waves.left.and.right.fill
            applewatch
            applewatch.and.arrow.forward
            applewatch.badge.checkmark
            applewatch.badge.exclamationmark
            applewatch.case.sizes
            applewatch.radiowaves.left.and.right
            applewatch.side.right
            applewatch.slash
            applewatch.watchface
            arrow.clockwise arrow.clockwise.circle arrow.clockwise.circle.fill arrow.clockwise.square arrow.clockwise.square.fill
            bandage bandage.fill
            battery.100percent
            battery.100percent.bolt
            battery.100percent.circle battery.100percent.circle.fill
            bed.double
            bed.double.badge.checkmark bed.double.badge.checkmark.fill
            bed.double.circle bed.double.circle.fill bed.double.fill
            bell
            bell.and.waves.left.and.right bell.and.waves.left.and.right.fill
            bell.badge bell.badge.circle bell.badge.circle.fill bell.badge.fill
            bell.badge.slash bell.badge.slash.fill
            bell.badge.waveform bell.badge.waveform.fill
            bell.badge.waveform.slash bell.badge.waveform.slash.fill
            bell.circle bell.circle.fill bell.fill
            bell.slash bell.slash.circle bell.slash.circle.fill bell.slash.fill
            bell.square bell.square.fill
            bolt.heart bolt.heart.fill
            brain brain.fill
            brain.filled.head.profile
            brain.head.profile brain.head.profile.fill
            chart.line.uptrend.xyaxis.circle chart.line.uptrend.xyaxis.circle.fill
            clock
            clock.arrow.trianglehead.2.counterclockwise.rotate.90
            clock.arrow.trianglehead.clockwise.rotate.90.path.dotted
            clock.arrow.trianglehead.counterclockwise.rotate.90
            clock.badge
            clock.badge.airplane clock.badge.airplane.fill
            clock.badge.checkmark clock.badge.checkmark.fill
            clock.badge.exclamationmark clock.badge.exclamationmark.fill
            clock.badge.fill
            clock.badge.questionmark clock.badge.questionmark.fill
            clock.badge.xmark clock.badge.xmark.fill
            clock.circle clock.circle.fill clock.fill
            cup.and.saucer cup.and.saucer.fill
            earbuds
            earbuds.bone.conduction
            earbuds.bone.conduction.left
            earbuds.bone.conduction.right
            earbuds.case earbuds.case.fill
            earbuds.in.ear
            earbuds.in.ear.left
            earbuds.in.ear.right
            earbuds.stemless
            earbuds.stemless.left
            earbuds.stemless.right
            flame.gauge.open
            fork.knife fork.knife.circle fork.knife.circle.fill
            gauge.chart.lefthalf.righthalf
            gauge.chart.leftthird.topthird.rightthird
            gauge.open
            gauge.open.righthalf.dotted.with.needle.and.arrow.trianglehead.backward
            gauge.open.with.lines.needle.33percent
            gauge.open.with.lines.needle.33percent.and.arrow.trianglehead.from.0percent.to.50percent
            gauge.open.with.lines.needle.33percent.and.arrowtriangle
            gauge.open.with.lines.needle.67percent.and.arrowtriangle
            gauge.open.with.lines.needle.67percent.and.arrowtriangle.and.car
            gauge.open.with.lines.needle.84percent.exclamation
            gauge.with.dots.needle.0percent
            gauge.with.dots.needle.100percent
            gauge.with.dots.needle.33percent
            gauge.with.dots.needle.50percent
            gauge.with.dots.needle.67percent
            gauge.with.dots.needle.bottom.0percent
            gauge.with.dots.needle.bottom.100percent
            gauge.with.dots.needle.bottom.50percent
            gauge.with.dots.needle.bottom.50percent.badge.minus
            gauge.with.dots.needle.bottom.50percent.badge.plus
            headphones headphones.circle headphones.circle.fill
            headphones.dots
            headphones.over.ear
            headphones.sensor.tag.radiowaves.left.and.right headphones.sensor.tag.radiowaves.left.and.right.fill
            headphones.slash
            heart
            heart.badge.bolt heart.badge.bolt.fill
            heart.badge.bolt.slash heart.badge.bolt.slash.fill
            heart.circle heart.circle.fill heart.fill
            heart.gauge.open
            heart.rectangle heart.rectangle.fill
            heart.slash heart.slash.circle heart.slash.circle.fill heart.slash.fill
            heart.square heart.square.fill
            heart.text.clipboard heart.text.clipboard.fill
            heart.text.square heart.text.square.fill
            hourglass
            hourglass.badge.eye
            hourglass.badge.lock
            hourglass.badge.plus
            hourglass.bottomhalf.filled
            hourglass.circle hourglass.circle.fill
            hourglass.tophalf.filled
            lungs lungs.fill
            metronome metronome.fill
            mug mug.fill
            music.note.arrow.trianglehead.clockwise
            music.note.house music.note.house.fill
            music.note.square.stack.fill
            music.note.tv music.note.tv.fill
            repeat
            repeat.1 repeat.1.circle repeat.1.circle.fill
            repeat.badge.xmark
            repeat.circle repeat.circle.fill
            ruler ruler.fill
            scope
            stopwatch stopwatch.fill
            takeoutbag.and.cup.and.straw takeoutbag.and.cup.and.straw.fill
            timer timer.circle timer.circle.fill timer.square
            waveform.path.ecg
            waveform.path.ecg.magnifyingglass
            waveform.path.ecg.rectangle waveform.path.ecg.rectangle.fill
            waveform.path.ecg.text.clipboard waveform.path.ecg.text.clipboard.fill
            """),
    ]
}
