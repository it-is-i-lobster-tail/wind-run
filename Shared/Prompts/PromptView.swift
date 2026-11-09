//
//  PromptView.swift
//  Wind Run
//

import SwiftUI

extension View {
    /// Asks the prompts still to ask on this device, one sheet at a time, once this view appears.
    func presentsPrompts() -> some View {
        modifier(PromptPresenter())
    }
}

private struct PromptPresenter: ViewModifier {
    @State private var queue = PromptQueue()

    func body(content: Content) -> some View {
        // Read here, so the sheet follows the queue as it moves on.
        let current = queue.current
        return content
            .sheet(item: Binding(
                get: { current },
                // Closing the sheet without answering counts as "Not Now".
                set: { prompt in
                    if prompt == nil { queue.decline() }
                }
            )) { prompt in
                PromptView(prompt: prompt, queue: queue)
            }
            .task { queue.showNext() }
    }
}

/// One prompt with its yes and no, on iPhone and Apple Watch.
struct PromptView: View {
    let prompt: Prompt
    let queue: PromptQueue

    var body: some View {
        ScrollView {
            VStack(spacing: Self.spacing) {
                Image(systemName: prompt.systemImage)
                    .font(Self.iconFont)
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)

                Text(prompt.title)
                    .font(Self.titleFont)
                    .multilineTextAlignment(.center)

                Text(prompt.message)
                    .font(Self.messageFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let content = prompt.content {
                    content()
                }

                buttons
                    .padding(.top, Self.spacing)
            }
            .padding()
        }
        // Health's permission sheet may be up while the yes is acted on.
        .interactiveDismissDisabled(queue.isAccepting || prompt.requiresAnswer)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    private var buttons: some View {
        VStack(spacing: Self.spacing) {
            Button {
                Task { await queue.accept() }
            } label: {
                ZStack {
                    // Keeps the button's size while the spinner shows.
                    Text(prompt.acceptTitle)
                        .opacity(queue.isAccepting ? 0 : 1)
                    if queue.isAccepting {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.onAccent)
            }
            .buttonStyle(.borderedProminent)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .disabled(!prompt.canAccept())

            #if os(iOS)
            // A choice gets a second button you can see, not a quiet "Not Now".
            if prompt.requiresAnswer {
                declineButton
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            } else {
                declineButton
                    .buttonStyle(.borderless)
                    .controlSize(.large)
            }
            #else
            declineButton
            #endif
        }
        .disabled(queue.isAccepting)
    }

    private var declineButton: some View {
        Button {
            queue.decline()
        } label: {
            Text(prompt.declineTitle)
                .frame(maxWidth: .infinity)
        }
    }

    #if os(watchOS)
    private static let spacing: CGFloat = 6
    private static let iconFont = Font.title2
    private static let titleFont = Font.headline
    private static let messageFont = Font.footnote
    #else
    private static let spacing: CGFloat = 12
    private static let iconFont = Font.system(size: 44)
    private static let titleFont = Font.title2.weight(.semibold)
    private static let messageFont = Font.body
    #endif
}

#Preview("Units prompt") {
    PromptView(prompt: .units, queue: PromptQueue(prompts: [.units]))
}

#if os(iOS)
#Preview("Body weight prompt") {
    PromptView(prompt: .bodyWeight, queue: PromptQueue(prompts: [.bodyWeight]))
}
#endif

#Preview("Heart rate prompt") {
    PromptView(prompt: .heartRate, queue: PromptQueue(prompts: [.heartRate]))
}

#Preview("Save runs prompt") {
    PromptView(prompt: .saveRunsToHealth, queue: PromptQueue(prompts: [.saveRunsToHealth]))
}
