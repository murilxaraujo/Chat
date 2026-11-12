//
//  Created by Alex.M on 23.06.2022.
//

import SwiftUI
import ExyteChat

struct ContentView: View {
    
    @State private var theme: ExampleThemeState = .accent
    @State private var color = Color(.exampleBlue)
    @State private var selectedExample: ExampleDestination?
    
    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selectedExample) {
                Section("Basic examples") {
                    NavigationLink(value: ExampleDestination.activeChat) {
                        Label("Active chat example", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink(value: ExampleDestination.simpleChat) {
                        Label("Simple chat example", systemImage: "message")
                    }
                    NavigationLink(value: ExampleDestination.comments) {
                        Label("Simple comments example", systemImage: "text.bubble")
                    }
                }
            }
            .navigationTitle("Chat examples")
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    themeControls
                }
            }
        } detail: {
            Group {
                if let selectedExample {
                    exampleView(for: selectedExample)
                } else {
                    ContentUnavailableView(
                        "Choose an example",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Select a chat example from the sidebar.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #else
        NavigationView {
            List {
                Section {
                    NavigationLink("Active chat example") {
                        exampleView(for: .activeChat)
                    }
                    
                    NavigationLink("Simple chat example") {
                        exampleView(for: .simpleChat)
                    }

                    NavigationLink("Simple comments example") {
                        exampleView(for: .comments)
                    }
                } header: {
                    Text("Basic examples")
                }
            }
            .navigationTitle("Chat examples")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    themeControls
                }
            }
        }
        .navigationViewStyle(.stack)
        #endif
    }

    private var themeControls: some View {
        HStack {
            Button(theme.title) {
                theme = theme.next()
            }
            ColorPicker("", selection: $color)
                .labelsHidden()
        }
        .fixedSize()
    }

    @ViewBuilder
    private func exampleView(for destination: ExampleDestination) -> some View {
        switch destination {
        case .activeChat:
            if theme.isAccent {
                ActiveChatExampleView()
                    .chatTheme(accentColor: color, images: theme.images)
            } else {
                ActiveChatExampleView()
                    .chatTheme(themeColor: color)
            }
        case .simpleChat:
            if theme.isAccent {
                ChatExampleView()
                    .chatTheme(accentColor: color, images: theme.images)
            } else {
                ChatExampleView()
                    .chatTheme(themeColor: color)
            }
        case .comments:
            CommentsExampleView()
                .chatTheme(.init(colors: .init(
                    inputSignatureBG: .white.opacity(0.5),
                    inputSignatureText: .black,
                    inputSignaturePlaceholderText: .black.opacity(0.7)
                )))
        }
    }
}

private enum ExampleDestination: Hashable {
    case activeChat
    case simpleChat
    case comments
}

/// An enum that lets us iterate through the different ChatTheme styles
enum ExampleThemeState: String {
    case accent
    case image
    case themed
    
    var title:String {
        self.rawValue.capitalized
    }
    
    func next() -> ExampleThemeState {
        switch self {
        case .accent:
            return .themed
        case .themed:
            return .image
        case .image:
            return .accent
        }
    }
    
    var images: ChatTheme.Images {
        switch self {
        case .accent, .themed: return .init()
        case .image:
            return .init(
                background: ChatTheme.Images.Background(
                    portraitBackgroundLight: Image("chatBackgroundLight"),
                    portraitBackgroundDark: Image("chatBackgroundDark"),
                    landscapeBackgroundLight: Image("chatBackgroundLandscapeLight"),
                    landscapeBackgroundDark: Image("chatBackgroundLandscapeDark")
                )
            )
        }
    }
    
    var isAccent: Bool {
        self != .themed
    }
}
