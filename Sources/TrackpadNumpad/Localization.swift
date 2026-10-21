import Foundation
import TrackpadCore

func L(_ key: String) -> String {
    AppLocalization.text(key, language: AppLanguage.load())
}
