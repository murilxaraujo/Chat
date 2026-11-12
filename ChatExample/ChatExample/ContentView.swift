//
//  Created by Alex.M on 23.06.2022.
//

import SwiftUI
import ExyteChat

struct ContentView: View {
    
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
        ColorPicker("Accent color", selection: $color)
            .labelsHidden()
    }

    @ViewBuilder
    private func exampleView(for destination: ExampleDestination) -> some View {
        switch destination {
        case .activeChat:
            ActiveChatExampleView()
                .tint(color)
        case .simpleChat:
            ChatExampleView()
                .tint(color)
        case .comments:
            CommentsExampleView()
                .tint(color)
        }
    }
}

private enum ExampleDestination: Hashable {
    case activeChat
    case simpleChat
    case comments
}
