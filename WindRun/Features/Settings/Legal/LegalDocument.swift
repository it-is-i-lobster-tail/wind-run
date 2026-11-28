//
//  LegalDocument.swift
//  Wind Run
//

import Foundation

/// A titled legal page shown from Settings → Legal.
///
/// The words here and in `PRIVACY.md` and `TERMS.md` at the top of the repository must match,
/// and `LegalDocumentTests` fails if they don't. Change both, and the date, together.
struct LegalDocument: Hashable {
    struct Section: Hashable {
        let heading: String
        let body: String
    }

    let title: String
    let lastUpdated: String
    let sections: [Section]
}

extension LegalDocument {
    static let privacyPolicy = LegalDocument(
        title: "Privacy Policy",
        lastUpdated: "November 27, 2026",
        sections: [
            Section(
                heading: "The Short Version",
                body: "Wind Run does not collect, sell or share any of your data. There are no accounts, no ads, no analytics and no tracking. The developer never sees your runs."
            ),
            Section(
                heading: "What Stays on Your Devices",
                body: "Your runs, routes, heart rate readings, steps, workouts, coach plans, injury reports and settings are stored on your iPhone and Apple Watch. Nothing is sent to the developer or to any server Wind Run runs, because there isn't one."
            ),
            Section(
                heading: "Location",
                body: "Wind Run uses your location while you record a run, including with the screen locked, to map and measure it. Each route is saved with its run on your device. It only leaves your device through iCloud Sync or Save workouts to Health, if you turn those on, or in a file you choose to share."
            ),
            Section(
                heading: "Motion & Fitness",
                body: "If you allow Motion & Fitness, Wind Run counts your steps for cadence, notices when you stop for auto-pause, and reads the barometer to measure hills for climb and calories. These readings are kept with your runs on your device."
            ),
            Section(
                heading: "Apple Health",
                body: "Apple Health is optional and off until you turn it on. With Save workouts to Health on, Wind Run adds each finished run or ride to Health as a workout with its distance, route and calories. With your permission it reads heart rate, resting heart rate, steps, distance, running power, and cycling cadence and power during a workout, your weight for calories, and your last 4 weeks of workouts when you set up the coach. Health data is used only to show and measure your runs inside Wind Run. It is never used for advertising, never sold, and never shared with anyone. Deleting a run can also remove its workout from Health when you ask. You can change what Wind Run may read or save at any time in the Health app or in iOS Settings."
            ),
            Section(
                heading: "Heart Rate Devices",
                body: "Heart rate comes through Apple's workout session from your Apple Watch, AirPods Pro 3, Powerbeats Pro 2 or a Bluetooth strap paired in iOS Settings. Each run notes which kinds of device recorded it, by hardware model and software version, never by the name you gave the device."
            ),
            Section(
                heading: "iCloud Sync",
                body: "iCloud Sync is off until you turn it on. With it on, Wind Run keeps a copy of your runs, routes, plans and settings, including your weight, heart rate settings and Starting Point pins, in your own private iCloud database, so a new iPhone can pick up where you left off. Only your Apple Account can read that copy, and Apple handles it under Apple's Privacy Policy. Turning iCloud Sync off deletes the iCloud copy."
            ),
            Section(
                heading: "Apple Watch",
                body: "Wind Run on Apple Watch records runs locally and sends finished runs directly to your paired iPhone. If you turn on iCloud Sync, the iPhone also syncs those runs to your private iCloud database. Settings such as units, call-outs and haptics, today's coach workouts and your saved workouts pass directly between your iPhone and watch."
            ),
            Section(
                heading: "Maps",
                body: "Route maps are drawn with Apple Maps. To show a map, your device downloads map images for that area from Apple, under Apple's Privacy Policy. Your route line is drawn on your device and is not sent to Apple Maps. To show the town a workout started in, and to search by place, Wind Run works out the parks, neighborhoods, towns and states a US workout went through on this iPhone, from map data that comes with the app. Points within 250 m of the start and end are skipped, so your home is never one of them. For a workout that started outside the US, Wind Run asks Apple Maps once for the town at a random point 50 to 150 m from the start, never the start itself. The places are kept only on this iPhone, and are left out of iCloud, backups and exports. To find your fastest stretches and runs that went the same way, search also keeps each run's best times and a rough outline of its route, in squares of about 150 m. These are kept only on this iPhone too, and are left out of iCloud, backups and exports. Each run keeps the time zone it started in, such as America/Los_Angeles, so its start time stays right after you travel. The time zone goes wherever the run goes, through iCloud Sync and Save workouts to Health, and is left out of exports."
            ),
            Section(
                heading: "Weather",
                body: "Weather for Runs, under Settings → Your Data, is off until you turn it on. With it on, after a run Wind Run asks Apple Weather once for that run's temperature, sky, wind and humidity. It sends only the middle of a square about 5 km across that the run started in, and the time of the run, never your route or where the run started. Apple Weather handles the request under Apple's Privacy Policy. The weather is kept with the run, and goes to iCloud with it if iCloud Sync is on."
            ),
            Section(
                heading: "Voice, Haptics and Live Activities",
                body: "Voice call-outs are spoken on your device from voice clips built into the app, or by the system voice. Haptics are played on your device. The Live Activity on your Lock Screen and in the Dynamic Island is updated by the app on your iPhone, with no push server."
            ),
            Section(
                heading: "Exports and Trace Logs",
                body: "Export Runs saves files only when you ask, and leaves out locations, dates, times, heart rate, names, weight and device names. GPS readings near where each run starts and finishes, 250 m unless you change it, are left out too. Under Settings → Your Data → Starting Point you can pick another distance, or pin places on a map to hide instead, such as home. Pins are kept with your settings and never go in an export. A run's weather goes in the export without its place or time. Trace logging, under Developer Tool, is off unless you turn it on. Its files stay on your iPhone and leave out places, clock times, typed words, names, heart rate and weight. Neither ever leaves your iPhone unless you share it yourself."
            ),
            Section(
                heading: "Third Parties",
                body: "Wind Run contains no third-party code, SDKs or services. It only uses Apple's own services, iCloud, Apple Health, Apple Maps and Apple Weather, as described above. The offline map data comes from Overture Maps and OpenStreetMap contributors and is part of the app, so nothing is sent to them. Settings → Legal → Offline Map Data lists its credits."
            ),
            Section(
                heading: "Deleting Your Data",
                body: "You can delete any run in the app. Turning iCloud Sync off deletes the copy in iCloud. Deleting Wind Run from a device deletes everything it kept on that device. Runs saved to Apple Health stay in Health until you delete them there."
            ),
            Section(
                heading: "Children",
                body: "Wind Run is intended only for adults 18 and older."
            ),
            Section(
                heading: "Public Source Code",
                body: "Wind Run's source code is public, so anyone can check this policy against the code at https://github.com/it-is-i-lobster-tail/wind-run."
            ),
            Section(
                heading: "Changes and Contact",
                body: "If this policy changes, the new version will be posted with a new date. Questions can be raised as an issue on the Wind Run GitHub repository."
            ),
        ]
    )

    static let termsAndConditions = LegalDocument(
        title: "Terms and Conditions",
        lastUpdated: "November 17, 2026",
        sections: [
            Section(
                heading: "Agreement",
                body: "By using Wind Run you agree to these terms and to the Privacy Policy. If you do not agree, do not use the app."
            ),
            Section(
                heading: "Adults Only",
                body: "Wind Run is only for people 18 and older. By using it, you confirm that you are at least 18."
            ),
            Section(
                heading: "Not Medical Advice",
                body: "Wind Run is a running log and training planner, not a doctor, coach or physical therapist, and not a medical device. Nothing in the app is medical, health or professional fitness advice, and it does not diagnose, treat or prevent any condition. Heart rate and other readings are not for medical use."
            ),
            Section(
                heading: "See a Medical Provider First",
                body: "Talk to a doctor or other qualified medical provider before starting any running or training plan, and before changing one. This matters most if you are pregnant, injured, recovering from surgery, taking medication, or have any heart, blood pressure, breathing, joint or other health condition."
            ),
            Section(
                heading: "Run at Your Own Risk",
                body: "Running, and especially speed work, long runs and racing, carries a real risk of injury, illness and death. You choose where, when, how far and how hard you run, and you voluntarily accept every risk of running, whether or not you follow anything shown in the app."
            ),
            Section(
                heading: "Stop if Something Is Wrong",
                body: "Stop running right away if you feel pain, chest pain or pressure, shortness of breath, dizziness, faintness, nausea, numbness, or anything else that feels wrong. Get medical help if it does not pass quickly. Do not run through pain."
            ),
            Section(
                heading: "Run Safely",
                body: "Obey traffic laws and stay aware of traffic, cyclists and other people. Keep your eyes on your route, not on your iPhone or watch, especially when crossing roads. Keep audio low enough to hear what is around you. Be seen in the dark, dress for the weather, take care in heat and cold, and drink enough water. Let someone know your route when running alone."
            ),
            Section(
                heading: "Measurements Are Estimates",
                body: "Distance, pace, time, heart rate, steps, climb, calories and other numbers come from GPS and sensors that can be wrong, sometimes by a lot. Do not rely on them for safety, medical or competitive decisions."
            ),
            Section(
                heading: "The Coach",
                body: "Coach plans are general and built only from what you tell the app and from your runs. The coach does not know your health, and its plans may not suit you. You decide whether to run each workout, and you can ease off, skip or stop at any time. Reporting an injury in the app only changes your plan. It is not a substitute for medical care."
            ),
            Section(
                heading: "No Guarantees",
                body: "Plans, workouts, call-outs and other suggestions in Wind Run are general and may not suit you. Results are not guaranteed. Use your own judgment and adjust or skip anything that is not right for you."
            ),
            Section(
                heading: "Provided As Is",
                body: "Wind Run is provided free and \"as is\", without warranties of any kind, express or implied, including fitness for a particular purpose. The app may contain errors, and your data may be lost. Keep your own records of anything important."
            ),
            Section(
                heading: "Limitation of Liability",
                body: "To the fullest extent allowed by law, the developer and contributors are not liable for any injury, illness, death, loss of data, or any direct, indirect, incidental or consequential damages arising from your use of Wind Run or from any running or exercise you do. You release them from all such claims."
            ),
            Section(
                heading: "Apple",
                body: "These terms are between you and the developer, not Apple. Apple is not responsible for Wind Run or its content, and has no duty to provide maintenance or support for it."
            ),
            Section(
                heading: "Changes",
                body: "These terms may change. Using Wind Run after a change means you accept the new terms. If any part of these terms cannot be enforced, the rest still applies."
            ),
        ]
    )
}
