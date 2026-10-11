import SwiftUI

/// Full-screen barcode display — this, not the complication, is the version
/// meant to actually be scanned: full watch-screen size instead of a
/// complication's tiny slot.
struct BarcodeWatchView: View {
    @StateObject private var receiver = WatchBarcodeReceiver.shared

    var body: some View {
        VStack(spacing: 8) {
            if let barcode = receiver.barcode, UPCABarcode.modules(for: barcode) != nil {
                // Official Whole Foods Market UPC-A barcode card matching the
                // supermarket discount card exactly (white card, guard bars, masked numbers).
                UPCABarcodeCard(input: barcode)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "barcode")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Set your barcode in the WF Schedule app on your iPhone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .fontDesign(receiver.roundedFont ? .rounded : .default)
        .onAppear {
            receiver.activate()
        }
    }
}
