import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A `UIDocumentPickerViewController` wrapper used in place of SwiftUI's
/// `.fileImporter` for audio import — `.fileImporter` has no API to seed a
/// starting directory, so it always opens wherever Files last was (NSP-153).
/// Seeding `directoryURL` with `AppEnvironment.defaultImportExportDirectoryURL`
/// opens straight into the "North-Star Promise" folder a user would
/// naturally drop a recording into. Same minimal `UIViewControllerRepresentable`
/// shape `ShareSheet` (`AudioPlayerCard.swift`) already uses for
/// `UIActivityViewController`.
struct AudioDocumentPicker: UIViewControllerRepresentable {
    let startingDirectory: URL?
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.mp3, .wav, .mpeg4Audio], asCopy: true)
        picker.directoryURL = startingDirectory
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
