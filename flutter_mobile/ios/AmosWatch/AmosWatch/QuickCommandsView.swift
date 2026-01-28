import SwiftUI

struct QuickCommandsView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var isLoading = false
    @State private var loadingAction: String?

    let quickCommands: [(icon: String, title: String, action: String)] = [
        ("bell.badge", "What needs attention?", "check_attention"),
        ("calendar", "Today's schedule", "show_schedule"),
        ("envelope", "New messages", "check_messages"),
        ("checkmark.circle", "Task summary", "task_summary"),
        ("chart.bar", "Campaign status", "campaign_status"),
        ("person.2", "Team updates", "team_updates"),
    ]

    var body: some View {
        List {
            ForEach(quickCommands, id: \.action) { command in
                Button(action: {
                    executeCommand(command.action)
                }) {
                    HStack {
                        Image(systemName: command.icon)
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        Text(command.title)
                            .font(.caption)

                        Spacer()

                        if loadingAction == command.action {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
            }

            // Custom voice command
            Section {
                NavigationLink(destination: VoiceInputView()) {
                    HStack {
                        Image(systemName: "mic")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        Text("Custom command...")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Commands")
    }

    private func executeCommand(_ action: String) {
        isLoading = true
        loadingAction = action

        connectivityManager.sendQuickAction(action)

        // Reset loading state after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isLoading = false
            loadingAction = nil
        }
    }
}

struct VoiceInputView: View {
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    @State private var voiceText = ""
    @State private var isSending = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Say your command")
                .font(.caption)
                .foregroundColor(.gray)

            // Text field with dictation
            TextField("Tap to speak", text: $voiceText)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)

            Button(action: sendCommand) {
                HStack {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text("Send")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(voiceText.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(voiceText.isEmpty || isSending)
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .navigationTitle("Voice")
    }

    private func sendCommand() {
        guard !voiceText.isEmpty else { return }

        isSending = true
        connectivityManager.sendVoiceCommand(voiceText)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
}

#Preview {
    QuickCommandsView()
        .environmentObject(WatchConnectivityManager())
}
