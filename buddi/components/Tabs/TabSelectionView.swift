//
//  TabSelectionView.swift
//  buddi
//
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Buddy", icon: "pawprint.fill", view: .buddy),
    TabModel(label: "Dashboard", icon: "square.grid.2x2", view: .home),
    TabModel(label: "Inbox", icon: "bell.fill", view: .inbox),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BuddiViewCoordinator.shared
    @State private var displayedView: NotchViews = BuddiViewCoordinator.shared.currentView
    @Namespace var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: displayedView == tab.view) {
                    withAnimation(.smooth) {
                        displayedView = tab.view
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == displayedView ? .white : .gray)
                .background {
                    if tab.view == displayedView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
            }
        }
        .clipShape(Capsule())
        .onAppear { displayedView = coordinator.currentView }
        .onChange(of: coordinator.currentView) { _, new in
            guard displayedView != new else { return }
            withAnimation(.smooth) { displayedView = new }
        }
    }
}

#Preview {
    BuddiHeader().environmentObject(BuddiViewModel())
}
