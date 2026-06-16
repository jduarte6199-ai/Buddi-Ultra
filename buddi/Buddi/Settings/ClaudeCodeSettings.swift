import AppKit
import Defaults
import SwiftUI

struct ClaudeCodeSettings: View {
    @State private var hooksInstalled = HookInstaller.isInstalled()
    @State private var selectedSound = BuddiSettings.notificationSound
    @ObservedObject private var usageService = UsageService.shared
    @ObservedObject private var buddyManager = BuddyManager.shared
    @Default(.buddySpeciesOverride) private var speciesOverride
    @Default(.buddyEyeOverride) private var eyeOverride
    @Default(.buddyHatOverride) private var hatOverride
    @Default(.buddyRarityOverride) private var rarityOverride

    private var currentSpecies: BuddySpecies {
        buddyManager.effectiveIdentity.species
    }

    private var currentEye: BuddyEye {
        buddyManager.effectiveIdentity.eye
    }

    private var currentHat: BuddyHat {
        buddyManager.effectiveIdentity.hat
    }

    private var currentRarity: BuddyRarity {
        buddyManager.effectiveIdentity.rarity
    }

    private var hasOverrides: Bool {
        speciesOverride != nil || eyeOverride != nil || hatOverride != nil || rarityOverride != nil
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Claude Code Hooks")
                    Spacer()
                    if hooksInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Install") {
                            HookInstaller.installIfNeeded()
                            hooksInstalled = HookInstaller.isInstalled()
                        }
                    }
                }
            } header: {
                Text("Integration")
            } footer: {
                Text("Forwards Claude Code events to Buddi via Unix socket.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Sound", selection: $selectedSound) {
                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Text(sound.rawValue).tag(sound)
                    }
                }
                .onChange(of: selectedSound) { _, newValue in
                    BuddiSettings.notificationSound = newValue
                    if let name = newValue.soundName {
                        NSSound(named: NSSound.Name(name))?.play()
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Plays when Claude finishes and is ready for input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Socket")
                    Spacer()
                    let active = FileManager.default.fileExists(atPath: "/tmp/buddi.sock")
                    Circle()
                        .fill(active ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(active ? "Active" : "Inactive")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Usage tracking")
                    Spacer()
                    if usageService.isAvailable {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Not available")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("OAuth login required for plan usage display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .showUsagePercent) {
                    Text("Show usage percentage")
                }
            } header: {
                Text("Usage")
            } footer: {
                Text("Show the percent number on the usage bars. Turn off to keep the bars but hide the % text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                buddyPreview
            } header: {
                Text("Buddy")
            } footer: {
                Text("Customize your buddy's appearance. Changes apply everywhere — notch, lock screen, and panels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                buddySpeciesGrid
            } header: {
                Text("Species")
            }

            Section {
                buddyEyeGrid
            } header: {
                Text("Eyes")
            }

            Section {
                buddyHatGrid
            } header: {
                Text("Hat")
            }

            Section {
                buddyRarityGrid
            } header: {
                Text("Rarity")
            } footer: {
                Text("Changes your buddy's color.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasOverrides {
                Section {
                    Button("Reset to Original") {
                        speciesOverride = nil
                        eyeOverride = nil
                        hatOverride = nil
                        rarityOverride = nil
                    }
                } footer: {
                    Text("Restore your buddy's original randomly-assigned appearance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if FileManager.default.fileExists(atPath: "/Applications/cmux.app") {
                Section {
                    HStack {
                        Text("Socket Control Mode")
                        Spacer()
                        Text("Automation mode")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("cmux")
                } footer: {
                    Text("To send messages from Buddi to cmux sessions, set Socket Control Mode to \"Automation mode\" in cmux Settings > Automation. This allows Buddi to communicate with cmux's Unix socket.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            hooksInstalled = HookInstaller.isInstalled()
            selectedSound = BuddiSettings.notificationSound
        }
    }

    private var buddyPreview: some View {
        HStack {
            Spacer()
            ASCIIFullSpriteView(
                animator: buddyManager.animator,
                identity: buddyManager.effectiveIdentity,
                fontSize: 14
            )
            Spacer()
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
    }

    private var buddySpeciesGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(BuddySpecies.allCases, id: \.self) { species in
                buddyCard(
                    preview: SpriteData.face(species: species, eye: currentEye),
                    title: species.rawValue.capitalized,
                    isSelected: currentSpecies == species
                ) {
                    speciesOverride = species.rawValue
                }
            }
        }
        .padding(8)
    }

    private var buddyEyeGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(BuddyEye.allCases, id: \.self) { eye in
                buddyCard(
                    preview: SpriteData.face(species: currentSpecies, eye: eye),
                    title: eye.name,
                    isSelected: currentEye == eye
                ) {
                    eyeOverride = eye.rawValue
                }
            }
        }
        .padding(8)
    }

    private var buddyHatGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(BuddyHat.allCases, id: \.self) { hat in
                let preview = hat == .none
                    ? "—"
                    : (SpriteData.hatLines[hat] ?? "").trimmingCharacters(in: .whitespaces)
                buddyCard(
                    preview: preview,
                    title: hat.rawValue.capitalized,
                    isSelected: currentHat == hat
                ) {
                    hatOverride = hat.rawValue
                }
            }
        }
        .padding(8)
    }

    private var buddyRarityGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(BuddyRarity.allCases, id: \.self) { rarity in
                Button {
                    rarityOverride = rarity.rawValue
                } label: {
                    VStack(spacing: 6) {
                        Text(rarity.stars)
                            .font(.system(size: 14))
                            .foregroundColor(Color(nsColor: rarity.nsColor))
                            .frame(width: 64, height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.black.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(currentRarity == rarity ? Color.accentColor : .clear, lineWidth: 2)
                            )

                        Text(rarity.rawValue.capitalized)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(currentRarity == rarity ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(currentRarity == rarity ? Color.accentColor : .clear)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    private func buddyCard(preview: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(preview)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(nsColor: buddyManager.effectiveIdentity.rarity.nsColor))
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
