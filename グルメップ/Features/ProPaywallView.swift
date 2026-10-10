import StoreKit
import SwiftUI

extension View {
    func proPaywall(isPresented: Binding<Bool>) -> some View {
        modifier(ProPaywallPresentation(isPresented: isPresented))
    }
}

private struct ProPaywallPresentation: ViewModifier {
    @Environment(ProOfferPresenter.self) private var offerPresenter
    @Environment(ProAccessController.self) private var proAccess
    @Binding var isPresented: Bool
    @State private var pendingOffer = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: {
            guard pendingOffer else { return }
            pendingOffer = false
            guard !proAccess.isProUnlocked else { return }
            offerPresenter.show(proAccess: proAccess)
        }) {
            ProPaywallView(onLimitedOffer: { pendingOffer = true })
                .presentationBackground(.clear)
        }
    }
}

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProAccessController.self) private var proAccess
    let limited: Bool
    let onLimitedOffer: () -> Void
    @State private var plans = ProSubscriptionPlans()
    @State private var selectedPlan: ProSubscriptionPlan = .annual

    init(limited: Bool = false, onLimitedOffer: @escaping () -> Void = {}) {
        self.limited = limited
        self.onLimitedOffer = onLimitedOffer
    }

    var body: some View {
        PaywallScreen(
            limited: limited,
            canClose: true,
            plans: plans,
            selectedPlan: $selectedPlan,
            close: close
        )
        .interactiveDismissDisabled()
        .task {
            await plans.prepare()
            if limited, plans.isConfigured, !plans.introductoryPlans.contains(.annual) {
                selectedPlan = .monthly
            }
        }
        .onChange(of: proAccess.isProUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .alert("購入情報", isPresented: Binding(
            get: { proAccess.errorMessage != nil },
            set: { if !$0 { proAccess.errorMessage = nil } }
        )) {
            Button("OK") { proAccess.errorMessage = nil }
        } message: {
            Text(proAccess.errorMessage ?? "")
        }
    }

    private func close() {
        guard !proAccess.isPurchasing else { return }
        if !limited {
            var wonLottery = Int.random(in: 0..<4) == 0
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTesting"),
               ProcessInfo.processInfo.arguments.contains("-forceLimitedPaywall") {
                wonLottery = true
            }
            #endif
            if !proAccess.isProUnlocked, plans.canShowLimitedOffer, wonLottery {
                onLimitedOffer()
            }
        }
        dismiss()
    }
}

private enum PaywallStyle {
    static let orange = Color(red: 240 / 255, green: 92 / 255, blue: 38 / 255)
    static let ink = Color(red: 31 / 255, green: 27 / 255, blue: 23 / 255)
    static let secondary = Color(red: 120 / 255, green: 110 / 255, blue: 99 / 255)
    static let pale = Color(red: 1, green: 241 / 255, blue: 224 / 255)
    static let border = Color(red: 232 / 255, green: 219 / 255, blue: 204 / 255)
    static let featureBorder = Color(red: 245 / 255, green: 144 / 255, blue: 108 / 255)
    static func serif(_ size: CGFloat) -> Font { .custom("HiraMinProN-W6", size: size, relativeTo: .title) }
}

private struct PaywallScreen: View {
    @Environment(ProAccessController.self) private var proAccess
    let limited: Bool
    let canClose: Bool
    let plans: ProSubscriptionPlans
    @Binding var selectedPlan: ProSubscriptionPlan
    let close: () -> Void
    @State private var legalPage: PaywallLegalPage?
    @State private var featureContentBottom: CGFloat = 0
    @State private var featureViewportHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                header
                hero
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    features
                        .padding(.bottom, 8)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: PaywallFeatureBottomKey.self,
                                    value: proxy.frame(in: .named("paywallFeatures")).maxY
                                )
                            }
                        }
                }
                .coordinateSpace(name: "paywallFeatures")
                .scrollIndicators(.hidden)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PaywallFeatureHeightKey.self, value: proxy.size.height)
                    }
                }
                .onPreferenceChange(PaywallFeatureBottomKey.self) { featureContentBottom = $0 }
                .onPreferenceChange(PaywallFeatureHeightKey.self) { featureViewportHeight = $0 }
                .overlay(alignment: .bottom) {
                    if featureContentBottom > featureViewportHeight + 1 {
                        LinearGradient(
                            colors: [.white.opacity(0), .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 36)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .padding(2)
                .background(.white)
                .overlay {
                    Rectangle()
                        .strokeBorder(PaywallStyle.featureBorder, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background {
                Image(limited ? "PaywallLimitedBackground" : "PaywallStandardBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                    .clipped()
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(PaywallStyle.ink)
        .tint(PaywallStyle.orange)
        .preferredColorScheme(.light)
        .accessibilityIdentifier(limited ? "limitedPaywall" : "standardPaywall")
        .sheet(item: $legalPage) { page in
            NavigationStack {
                Group {
                    switch page {
                    case .terms: TermsView()
                    case .privacy: PrivacyPolicyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { legalPage = nil }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(limited ? "PaywallLimitedCrown" : "PaywallCrown")
                .resizable().scaledToFit()
                .frame(width: limited ? 18.3957 : 21.7404, height: limited ? 22 : 26)
                .frame(width: 21.7404, height: 26)
                .accessibilityHidden(true)
            Text("グルメップ").font(PaywallStyle.serif(15))
            Text("Pro").font(PaywallStyle.serif(15)).foregroundStyle(PaywallStyle.orange)
            Spacer()
            if canClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 10)
                .disabled(proAccess.isPurchasing)
                .accessibilityLabel("Paywallを閉じる")
                .accessibilityIdentifier("paywallClose")
            } else {
                Color.clear.frame(width: 44, height: 36).accessibilityHidden(true)
            }
        }
        .frame(height: 36)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: limited ? 12 : 14) {
            if limited {
                VStack(alignment: .leading, spacing: 10) {
                    Text("初回登録者限定")
                        .font(PaywallStyle.serif(20))
                        .foregroundStyle(.white)
                        .frame(width: 213, height: 31)
                        .background(Color(red: 224 / 255, green: 74 / 255, blue: 20 / 255), in: RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("この表示が出た方だけの").font(PaywallStyle.serif(30)).minimumScaleFactor(0.75)
                        Text("特別割引価格").font(PaywallStyle.serif(35)).foregroundStyle(PaywallStyle.orange)
                    }
                    .lineLimit(1)
                }
                .background(alignment: .topTrailing) {
                    Image("PaywallLimitedGold").resizable().frame(width: 68.566, height: 82)
                        .offset(y: 24).allowsHitTesting(false).accessibilityHidden(true)
                }
            } else {
                Text("いつもの外食を\nもっと楽しく")
                    .font(PaywallStyle.serif(34))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .trailing) {
                        ZStack(alignment: .topLeading) {
                            Image("PaywallGlow").resizable().frame(width: 138.804, height: 166)
                            Image("PaywallGoldAccent").resizable().frame(width: 18.3957, height: 22).offset(x: 9, y: 30)
                            Image("PaywallCrown").resizable().scaledToFit().frame(width: 125, height: 141).offset(x: 16, y: 1)
                        }
                        .frame(width: 139, height: 96, alignment: .top)
                        .accessibilityHidden(true)
                    }
            }
            heading("豊富な追加機能", subtitle: "外食好きの皆さんのための、プレミアムな追加機能を豊富にご用意しました。")
        }
    }

    private var features: some View {
        VStack(spacing: 0) {
            feature("Bookmark", "次に食べたい", "次回のメニューを保存して、再訪時に確認", width: 14, height: 18)
            feature("Chart", "年間・月間ごはんレポート", "訪問数や高評価店を自動集計", width: 22, height: 17)
            feature("Sliders", "高度な絞り込み", "評価・写真・タグで条件を保存", width: 18, height: 18)
            feature("Photo", "写真の振り返り", "年・月別写真と共有コラージュ", width: 20, height: 18)
            feature("Pencil", "投稿画像メーカー", "4種類のProテンプレート", width: 19.7717, height: 19.7717)
            feature("Pin", "地図Pro", "訪問密度と近くの行きたいお店", width: 18, height: 22)
            feature("Sun", "自分好みにカスタマイズ", "テーマ色・列数・カード表示", width: 22, height: 22)
        }
        .background(.white)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String, width: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image((limited ? "PaywallLimited" : "Paywall") + icon)
                .resizable().frame(width: width, height: height)
                .frame(width: 40, height: 40)
                .background(PaywallStyle.pale, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(detail).font(.system(size: 10)).foregroundStyle(PaywallStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            heading(limited ? "初回登録者限定プラン" : "プランを選ぶ", subtitle: limited ? "初年度は限定価格、2年目以降は通常価格（月額プラン・年額プラン共通）" : "月額・年額から選べます")
            HStack(spacing: 10) {
                planCard(.monthly)
                planCard(.annual)
            }
            Button {
                Task { await proAccess.purchase(product: plans.products[selectedPlan]) }
            } label: {
                HStack {
                    if proAccess.isPurchasing { ProgressView().tint(.white) }
                    Text(limited ? "今だけの限定価格でProを始める" : "Proを始める")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(PaywallStyle.orange, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(proAccess.isPurchasing || !plans.canPurchase(selectedPlan, limited: limited))
            .accessibilityIdentifier("paywallPurchase")
            if !plans.isLoading && !plans.canPurchase(selectedPlan, limited: limited) {
                Button("購入情報を再読み込み") { Task { await plans.prepare() } }
                    .font(.system(size: 10))
            }
            VStack(spacing: 7) {
                Text("自動更新・いつでも解約できます").font(.system(size: 10))
                HStack(spacing: 16) {
                    Button("購入を復元") { Task { await proAccess.restorePurchases() } }
                        .disabled(proAccess.isLoading || proAccess.isPurchasing)
                    Button("利用規約") { legalPage = .terms }
                    Button("プライバシー") { legalPage = .privacy }
                }
                .font(.system(size: 9))
                .buttonStyle(.plain)
            }
            .foregroundStyle(PaywallStyle.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private func heading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 15, weight: .bold))
            Text(subtitle).font(.system(size: 10)).foregroundStyle(PaywallStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planCard(_ plan: ProSubscriptionPlan) -> some View {
        let selected = selectedPlan == plan
        return Button { selectedPlan = plan } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(plan.title).font(.system(size: 12, weight: .bold))
                    Spacer(minLength: 2)
                    if selected {
                        Text("選択中").font(.system(size: 8, weight: .bold)).foregroundStyle(PaywallStyle.orange)
                    } else {
                        Circle().stroke(PaywallStyle.border, lineWidth: 1).frame(width: 18, height: 22)
                    }
                }
                .frame(height: 22)
                Text("\(plans.price(for: plan, limited: limited)) / \(plan.unit)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(selected ? PaywallStyle.orange : PaywallStyle.ink)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Group {
                    if limited {
                        Text("初年度 \(plans.price(for: plan, limited: true))/\(plan.unit)\n2年目以降 \(plans.price(for: plan, limited: false))/\(plan.unit)")
                    } else if plan == .monthly {
                        Text("月払い")
                    } else if let product = plans.products[plan] {
                        Text("1か月あたり \((product.price / 12).formatted(product.priceFormatStyle))")
                    } else {
                        Text("1か月あたり375円")
                    }
                }
                .font(.system(size: 9)).foregroundStyle(PaywallStyle.secondary)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(height: limited ? (selected ? 150 : 136) : (selected ? 140 : 126))
            .background(selected ? PaywallStyle.pale : .white, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(selected ? PaywallStyle.orange : PaywallStyle.border, lineWidth: selected ? 2 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("paywallPlan_\(plan.rawValue)")
    }
}

private enum PaywallLegalPage: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
}

private struct PaywallFeatureBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct PaywallFeatureHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview("標準Paywall") {
    PaywallScreen(limited: false, canClose: true, plans: ProSubscriptionPlans(), selectedPlan: .constant(.annual), close: {})
        .environment(ProAccessController())
}

#Preview("初回登録者限定Paywall") {
    PaywallScreen(limited: true, canClose: true, plans: ProSubscriptionPlans(), selectedPlan: .constant(.annual), close: {})
        .environment(ProAccessController())
}
