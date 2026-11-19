//
//  InterfaceOrientation.swift
//  Wind Run
//

import SwiftUI
import UIKit

/// The app stays upright, except while a page that asks to turn sideways is showing, such as a run's charts,
/// which get more room across in landscape.
enum InterfaceOrientation {
    /// Pages showing now that may turn sideways. A count, since a full screen chart opens over the run page
    /// and either can go first.
    private static var landscapeRequests = 0

    /// What the app's windows may turn to right now. The app delegate hands this to UIKit.
    static var supported: UIInterfaceOrientationMask {
        landscapeRequests > 0 ? .allButUpsideDown : .portrait
    }

    fileprivate static func allowLandscape() {
        landscapeRequests += 1
        if landscapeRequests == 1 { refresh() }
        #if DEBUG
        if RunDetailDemo.turnsSideways {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        #endif
    }

    fileprivate static func endLandscape() {
        landscapeRequests = max(landscapeRequests - 1, 0)
        // A moment later, so a sideways page opening over this one, or this one showing again as one closes
        // over it, claims landscape first and the screen doesn't flick upright and back.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard landscapeRequests == 0 else { return }
            refresh()
        }
    }

    /// Asks UIKit to read `supported` again, and turns the screen upright when it's sideways and may no
    /// longer be.
    private static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                // Every screen presented in the window, since the topmost one decides.
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            if landscapeRequests == 0, scene.effectiveGeometry.interfaceOrientation.isLandscape {
                Trace.log(.screen, "Turn upright")
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                    Trace.error("Turn upright", error)
                }
            }
        }
    }
}

/// Hands UIKit the orientations the app may turn to, which change with the page showing.
final class WindRunAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        InterfaceOrientation.supported
    }
}

extension View {
    /// Lets the screen turn sideways while this page is showing. The rest of the app stays upright.
    func allowsLandscape() -> some View {
        modifier(LandscapeAllowance())
    }
}

private struct LandscapeAllowance: ViewModifier {
    /// So an extra appear or disappear doesn't count twice.
    @State private var isAllowing = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isAllowing else { return }
                isAllowing = true
                InterfaceOrientation.allowLandscape()
            }
            .onDisappear {
                guard isAllowing else { return }
                isAllowing = false
                InterfaceOrientation.endLandscape()
            }
    }
}
