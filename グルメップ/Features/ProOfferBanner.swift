import Observation
import SwiftUI
import UIKit

/// A non-key window lets the invitation float above an existing sheet without
/// changing navigation or intercepting touches outside the banner.
@MainActor
@Observable
final class ProOfferPresenter {
    @ObservationIgnored private var window: ProOfferWindow?

    func show(proAccess: ProAccessController) {
        guard !proAccess.isProUnlocked,
              let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive && $0.windows.contains(where: \.isKeyWindow) })
        else { return }
        hide()
        let overlay = ProOfferWindow(windowScene: scene)
        overlay.frame = scene.coordinateSpace.bounds
        overlay.backgroundColor = .clear
        overlay.windowLevel = .normal + 1
        let host = UIHostingController(rootView: ProOfferOverlay(
            close: { [weak self] in self?.hide() },
            registerHitView: { [weak overlay] in overlay?.bannerHitView = $0 },
            clearHitArea: { [weak overlay] in overlay?.bannerHitView = nil },
            updatePresentation: { [weak overlay] in overlay?.isPresentingPaywall = $0 }
        ).environment(proAccess))
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        window = overlay
        overlay.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}

private final class ProOfferWindow: UIWindow {
    weak var bannerHitView: UIView?
    var isPresentingPaywall = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isPresentingPaywall { return super.hitTest(point, with: event) }
        guard let bannerHitView,
              bannerHitView.window === self,
              bannerHitView.bounds.contains(bannerHitView.convert(point, from: self))
        else { return nil }
        // Never pass a touch inside the banner down to the app's window,
        // even if UIKit's normal hit test finds no opaque descendant.
        return super.hitTest(point, with: event) ?? rootViewController?.view
    }
}

/// Read the actual UIKit view's bounds in window coordinates at touch time.
/// SwiftUI's global coordinate space is not a UIWindow coordinate contract.
private struct ProOfferHitRegion: UIViewRepresentable {
    let register: (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        register(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        register(uiView)
    }
}

private struct ProOfferOverlay: View {
    @Environment(ProAccessController.self) private var proAccess
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let close: () -> Void
    let registerHitView: (UIView) -> Void
    let clearHitArea: () -> Void
    let updatePresentation: (Bool) -> Void
    @State private var visible = false
    @State private var showsPaywall = false
    @State private var closing = false

    var body: some View {
        Color.clear
            .overlay(alignment: .top) {
                if visible {
                    ProOfferBanner(open: openOffer, close: dismissBanner)
                        .background(ProOfferHitRegion(register: registerHitView))
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .gesture(DragGesture().onEnded { value in
                            if value.translation.height < -20 { dismissBanner() }
                        })
                        .transition(reduceMotion ? .opacity : .move(edge: .top))
                }
            }
            .task {
                withAnimation(.easeOut(duration: 0.35)) { visible = true }
                do {
                    try await Task.sleep(for: .seconds(6))
                    if !showsPaywall { dismissBanner() }
                } catch { }
            }
            .onChange(of: proAccess.isProUnlocked) { _, unlocked in
                if unlocked && !showsPaywall { dismissBanner() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && !showsPaywall { dismissBanner() }
            }
            .fullScreenCover(isPresented: $showsPaywall, onDismiss: close) {
                ProPaywallView(limited: true)
                    .presentationBackground(.clear)
            }
    }

    private func openOffer() {
        guard !closing, !proAccess.isProUnlocked else { return }
        updatePresentation(true)
        showsPaywall = true
    }

    private func dismissBanner() {
        guard !closing, !showsPaywall else { return }
        closing = true
        clearHitArea()
        withAnimation(.easeIn(duration: 0.25)) { visible = false }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.25))
            close()
        }
    }
}

private struct ProOfferBanner: View {
    let open: () -> Void
    let close: () -> Void
    private let orange = Color(red: 240 / 255, green: 92 / 255, blue: 38 / 255)
    private let ink = Color(red: 31 / 255, green: 27 / 255, blue: 23 / 255)

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image("PaywallCrown")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 44)
                    .frame(width: 58, height: 58)
                    .background(Color(red: 1, green: 241 / 255, blue: 224 / 255), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("初回限定のご案内")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(orange)
                        .padding(.trailing, 20)
                    Text("あなただけの限定価格を")
                        .font(.system(size: 15, weight: .bold))
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 8) {
                            Text("ご用意しました。")
                                .font(.system(size: 15, weight: .bold))
                            Spacer(minLength: 0)
                            actionLabel
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ご用意しました。")
                                .font(.system(size: 15, weight: .bold))
                            actionLabel
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ink)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(Color(red: 1, green: 252 / 255, blue: 247 / 255), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(red: 1, green: 181 / 255, blue: 108 / 255), lineWidth: 1)
            }
            .shadow(color: Color(red: 194 / 255, green: 110 / 255, blue: 38 / 255).opacity(0.12), radius: 6, x: 0, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("初回限定のご案内。あなただけの限定価格をご用意しました。プランを見る")
        .accessibilityIdentifier("limitedOfferBanner")
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 120 / 255, green: 110 / 255, blue: 99 / 255))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("限定価格の案内を閉じる")
        }
        .preferredColorScheme(.light)
    }

    private var actionLabel: some View {
        HStack(spacing: 5) {
            Text("プランを見る").font(.system(size: 12, weight: .bold))
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(orange)
        .fixedSize()
    }
}

#Preview("初回限定通知バナー") {
    ProOfferBanner(open: {}, close: {})
        .padding(12)
}
