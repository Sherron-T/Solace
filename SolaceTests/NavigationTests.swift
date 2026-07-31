import XCTest
@testable import Solace

@MainActor
final class NavigationTests: XCTestCase {
    func testMoodEnergyConfirmAndSafetyRoutes() {
        let model = makeModel()

        model.openMood()
        XCTAssertEqual(model.screen, .mood)
        model.selectMood(2)
        model.confirmMood()
        XCTAssertEqual(model.screen, .energy)
        model.selectEnergy(1)
        XCTAssertEqual(model.screen, .confirm)

        model.openMood()
        model.selectMood(4)
        model.confirmMood()
        XCTAssertEqual(model.screen, .safety)
    }

    func testVoiceCheckinRoutesToEnergyConfirmOrSafety() {
        let model = makeModel()

        model.voiceCheckin(mood: 1, energy: nil)
        XCTAssertEqual(model.screen, .energy)
        model.voiceCheckin(mood: 0, energy: 2)
        XCTAssertEqual(model.screen, .confirm)
        model.voiceCheckin(mood: 4, energy: nil)
        XCTAssertEqual(model.screen, .safety)
    }

    func testExitingMoodAndSSIWorkflows() {
        let model = makeModel()
        model.openMood()
        model.goHome()
        XCTAssertEqual(model.screen, .home)

        model.openBoost()
        XCTAssertEqual(model.screen, .boost)
        model.openSafety()
        XCTAssertEqual(model.screen, .safety)
    }

    func testSSIForwardBackAndSafetySkip() {
        var navigation = SSIStageHistory()
        XCTAssertEqual(navigation.stage, .landing)
        XCTAssertEqual(navigation.advance(highHopelessness: false), .consent)
        XCTAssertEqual(navigation.advance(highHopelessness: false), .preHope1)
        XCTAssertEqual(navigation.goBack(), .consent)

        navigation.jump(to: .preHope4)
        XCTAssertEqual(navigation.advance(highHopelessness: false), .preReadiness)
        XCTAssertEqual(navigation.goBack(), .preHope4)
        XCTAssertEqual(navigation.advance(highHopelessness: true), .safetyOffer)
    }

    func testVoiceBackNavigationUsesScreenHistory() {
        let model = makeModel()
        model.openMood()
        model.confirmMood()
        XCTAssertEqual(model.screen, .energy)
        model.voiceGoBack()
        XCTAssertEqual(model.screen, .mood)
        model.voiceGoBack()
        XCTAssertEqual(model.screen, .home)
    }

    func testCareBridgeNamesAreEditable() {
        let model = makeModel()
        model.setPatientName("Jordan")
        model.setCareTeamName("Marie")
        XCTAssertEqual(model.patientName, "Jordan")
        XCTAssertEqual(model.careTeamName, "Marie")
    }

    func testHiddenHackathonHistorySeedsPastCareBridgeDays() {
        let model = makeModel()
        model.setPatientName("Jordan")
        model.loadHackathonCareBridgeHistory()

        XCTAssertEqual(model.bridge.feed.count, 12)
        XCTAssertTrue(model.bridge.feed.allSatisfy { $0.text.contains("Jordan") })
        XCTAssertEqual(model.weekDots.filter(\.isLogged).count, 6)
        let days = Set(model.bridge.feed.map {
            Calendar.current.startOfDay(for: $0.date)
        })
        XCTAssertEqual(days.count, 7)
    }

    private func makeModel() -> AppModel {
        let suite = "SolaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppModel(store: defaults,
                        bridge: CareBridge(persistenceEnabled: false),
                        publishesSharedState: false)
    }
}
