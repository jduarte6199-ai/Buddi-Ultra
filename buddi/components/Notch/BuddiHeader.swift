//
//  BuddiHeader.swift
//  buddi
//
//

import Defaults
import SwiftUI

struct BuddiHeader: View {
    @EnvironmentObject var vm: BuddiViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BuddiViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    // Resolved once per launch (render path must not touch the disk), and by
    // bundle id so any install location (/Applications, ~/Applications) works.
    private static let loomURL: URL? =
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.loom.desktop")

    /// Posts cmd+shift+L (Loom's default start/stop recording shortcut).
    /// Requires the Accessibility permission to inject events.
    private static func postLoomRecordShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyL: CGKeyCode = 37
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyL, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyL, keyDown: false)
        down?.flags = [.maskCommand, .maskShift]
        up?.flags = [.maskCommand, .maskShift]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.shelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        // Quick Loom: raises the Loom recorder so a recording
                        // is one click away. Only shown when Loom is installed.
                        if let loomURL = Self.loomURL {
                            Button(action: {
                                NSWorkspace.shared.open(loomURL)
                                // With Accessibility granted, fire Loom's
                                // global shortcut (default cmd+shift+L) so
                                // one click starts the recording; without
                                // the permission, the recorder just opens.
                                if AXIsProcessTrusted() {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        Self.postLoomRecordShortcut()
                                    }
                                }
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "video.circle.fill")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Open Loom recorder")
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }

                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            BuddiBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BuddiHeader().environmentObject(BuddiViewModel())
}
