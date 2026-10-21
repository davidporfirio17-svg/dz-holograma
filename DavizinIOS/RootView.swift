import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if appState.isAuthenticated {
                HomeView(onContinue: {})
            } else {
                KeyGateView(onSuccess: {})
            }
        }
        .animation(.easeInOut(duration: 0.4), value: appState.isAuthenticated)
    }
}
