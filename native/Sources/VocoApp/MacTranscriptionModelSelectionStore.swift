import Foundation
import VocoAppCore

@MainActor
final class MacTranscriptionModelSelectionStore: TranscriptionModelSelectionStoring {
    private enum Keys {
        static let selection = "transcription.modelSelection"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selection: TranscriptionModelSelection {
        guard let data = defaults.data(forKey: Keys.selection),
              let selection = try? decoder.decode(TranscriptionModelSelection.self, from: data)
        else {
            return .default
        }

        return selection
    }

    func saveSelection(_ selection: TranscriptionModelSelection) {
        do {
            let data = try encoder.encode(selection)
            defaults.set(data, forKey: Keys.selection)
        } catch {
            NSLog("Voco: Unable to save transcription model selection: \(error.localizedDescription)")
        }
    }
}
