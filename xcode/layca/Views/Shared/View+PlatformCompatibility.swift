import SwiftUI

extension View {
    @ViewBuilder
    func laycaHideNavigationBar() -> some View {
#if os(iOS) || os(visionOS)
        self.navigationBarHidden(true)
#else
        self
#endif
    }

    @ViewBuilder
    func laycaApplyTextInputAutocorrectionPolicy() -> some View {
#if os(iOS) || os(visionOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self
#endif
    }

    @ViewBuilder
    func laycaApplyTabBarBackgroundStyle() -> some View {
#if os(iOS) || os(visionOS)
        self
#else
        self
#endif
    }

    @ViewBuilder
    func laycaApplyNavigationBarChrome(backgroundColor: Color) -> some View {
#if os(iOS) || os(visionOS)
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#else
        self
#endif
    }
}
