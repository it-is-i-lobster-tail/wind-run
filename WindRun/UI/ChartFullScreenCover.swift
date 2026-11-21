import SwiftUI

extension View {
    func chartFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                content().navigationTransition(.crossFade)
            } else {
                content()
            }
            #else
            content()
            #endif
        }
    }
}
