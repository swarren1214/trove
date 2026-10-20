import SwiftUI

/// The first launch: what Trove does, how it keeps documents private, and the Face ID lock.
/// The household step follows (HearthKit's, over everything) once this is done.
struct OnboardingView: View {
    @Environment(AppLock.self) private var lock
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.faceIDLock) private var faceIDLock = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(Brand.sky, in: .rect(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                    Text("Welcome to Trove")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Your family’s important papers, and where the originals are.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    point("doc.viewfinder", "Scan once", "Trove reads the type, name and dates on this \(DeviceName.current), and keeps every photo exactly as you took it.")
                    point("mappin.and.ellipse", "Know where the original is", "The fire safe, the deposit box, the attorney. Never hunt for a birth certificate again.")
                    point("calendar.badge.exclamationmark", "Before anything expires", "Passports nine months ahead, registrations six weeks ahead, with what renewing takes.")
                    point("lock.shield", "Private to your family", "Encrypted in your family’s iCloud. Nothing goes to Hearth’s servers. Numbers stay hidden until Face ID.")
                }
                Toggle(isOn: Binding(get: { faceIDLock }, set: { faceIDLock = $0 && lock.canLock() })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock with \(lock.biometryName)").font(.headline)
                        Text("Ask every time Trove opens.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Get Started", systemImage: nil) {
                withAnimation { onboarded = true }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.ink)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
