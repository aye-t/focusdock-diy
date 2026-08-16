import Foundation
import Testing
@testable import FocusDockMac

@Suite("App settings migration")
struct AppSettingsMigrationTests {
    @Test("仅开启番茄钟时自动使用独立图标")
    func timerOnlyUsesStandaloneSurface() {
        var settings = AppSettings()
        settings.floatingLayout = .combinedBar
        settings.showTimerPanel = true
        settings.showReminderPanel = false

        #expect(settings.usesStandaloneTimerSurface)
    }

    @Test("番茄钟与提醒同时开启时保留合并控制条")
    func timerAndReminderCanStillUseCombinedBar() {
        var settings = AppSettings()
        settings.floatingLayout = .combinedBar
        settings.showTimerPanel = true
        settings.showReminderPanel = true

        #expect(!settings.usesStandaloneTimerSurface)
    }

    @Test("Maps removed legacy pet species without rejecting the saved app state")
    func decodesLegacyPetSpecies() throws {
        let data = Data(#"{"petSpecies":"tomato","focusMinutes":25}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.petSpecies == .cat)
        #expect(settings.focusMinutes == 25)
    }

    @Test("Preserves current pet species")
    func decodesCurrentPetSpecies() throws {
        let data = Data(#"{"petSpecies":"dog"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.petSpecies == .dog)
    }

    @Test("Preserves independently enabled pet and reminder card")
    func preservesPetAndReminderCardCombination() throws {
        let data = Data(#"{"showPetPanel":true,"showReminderPanel":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.showPetPanel)
        #expect(settings.showReminderPanel)
    }

    @Test("Migrates removed compact floating layout to the combined bar")
    func migratesCompactFloatingLayout() throws {
        let data = Data(#"{"floatingLayout":"compactCircles"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.floatingLayout == .combinedBar)
    }
}
