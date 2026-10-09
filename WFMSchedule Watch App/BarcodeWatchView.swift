import SwiftUI

/// Full-screen barcode display — this, not the complication, is the version
/// meant to actually be scanned: full watch-screen size instead of a
/// complication's tiny slot.
struct BarcodeWatchView: View {
    @StateObject private var receiver = WatchBarcodeReceiver.shared

    var body: some View {
        VStack(spacing: 8) {
            if let barcode = receiver.barcode, let modules = Code128Barcode.modules(for: barcode) {
                // The same Code 128 ("491" + TM ID + "0") the phone previews and the
                // complication draws, black bars on a white card so it scans.
                Code128BarsShape(modules: modules)
                    .fill(Color.black)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .background(.white, in: .rect(cornerRadius: 8))
                Text(verbatim: SecureTMID.masked)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
