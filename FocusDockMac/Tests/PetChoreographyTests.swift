import AppKit
import XCTest
@testable import FocusDockMac

final class PetChoreographyTests: XCTestCase {
    func testAllNineteenPosesAreUsedByCompanionSequences() {
        let moods: [PetMood] = [
            .idle, .focus, .paused, .rest, .celebrate,
            .drink, .eye, .stretch, .wave,
        ]
        let used = Set(moods.flatMap(PetChoreography.sequence(for:)))

        XCTAssertEqual(used, Set(PetPose.allCases))
        XCTAssertEqual(used.count, 19)
    }

    func testSceneReminderMoodsRemainOnTheirSemanticPose() {
        XCTAssertEqual(PetChoreography.sequence(for: .drink), [.drink])
        XCTAssertEqual(PetChoreography.sequence(for: .eye), [.eye])
        XCTAssertEqual(PetChoreography.sequence(for: .stretch), [.stretch])
        XCTAssertEqual(PetChoreography.sequence(for: .wave), [.wave])
    }

    func testPetVisualMetricsUseOneSpeciesIndependentScale() {
        XCTAssertEqual(PetVisualMetrics.visibleSide(for: 184), 150.88, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.countdownBoardWidth(for: 184), 180.32, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.countdownBoardHeight(for: 184), 51.572, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.reminderCardWidth(for: 184), 208, accuracy: 0.001)

        let square = PetVisualMetrics.visibleContentSize(
            imageSize: CGSize(width: 512, height: 512),
            settingSize: 184
        )
        XCTAssertEqual(square.width, 150.88, accuracy: 0.001)
        XCTAssertEqual(square.height, 150.88, accuracy: 0.001)

        let landscape = PetVisualMetrics.visibleContentSize(
            imageSize: CGSize(width: 768, height: 512),
            settingSize: 184
        )
        XCTAssertEqual(landscape.width, 150.88, accuracy: 0.001)
        XCTAssertEqual(landscape.height, 100.586, accuracy: 0.001)
        XCTAssertEqual(
            PetVisualMetrics.countdownBoardOffset(
                for: 184,
                visibleTopExtent: 136
            ),
            160,
            accuracy: 0.001
        )
    }

    func testPetVisualMetricsStayReadableAtSliderExtremes() {
        XCTAssertEqual(PetVisualMetrics.clampedSettingSize(60), 88)
        XCTAssertEqual(PetVisualMetrics.clampedSettingSize(184), 184)
        XCTAssertEqual(PetVisualMetrics.clampedSettingSize(260), 220)
        XCTAssertEqual(PetVisualMetrics.petPanelVerticalSafetyArea(), 43)
        XCTAssertEqual(PetVisualMetrics.avatarCanvasHeight(for: 88), 132)
        XCTAssertEqual(PetVisualMetrics.avatarCanvasHeight(for: 220), 264)
        XCTAssertEqual(PetVisualMetrics.countdownBoardWidth(for: 88), 86.24, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.countdownBoardWidth(for: 220), 215.6, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.countdownBoardHeight(for: 88), 24.665, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.countdownBoardHeight(for: 220), 61.662, accuracy: 0.001)
        XCTAssertEqual(PetVisualMetrics.reminderCardWidth(for: 88), 208)
        XCTAssertEqual(PetVisualMetrics.reminderCardWidth(for: 220), 246.4, accuracy: 0.001)
    }

    func testExpandedPetPanelFitsTheCompleteTodayPlanPopover() {
        XCTAssertEqual(FloatingTodayPlanMetrics.width, 270)
        XCTAssertEqual(FloatingTodayPlanMetrics.height, 250)

        let minimumPanelHeight = FloatingTodayPlanMetrics.height
            + PetVisualMetrics.avatarCanvasHeight(for: PetVisualMetrics.minimumSettingSize)
            + PetVisualMetrics.petPanelVerticalSafetyArea()
        XCTAssertEqual(minimumPanelHeight, 425)
    }

    func testPetPanelNativeSizeTracksTheSameExpansionStateAsItsContent() {
        XCTAssertEqual(
            PetPanelMetrics.size(petSize: 140, isExpanded: false, hasCompletion: false),
            NSSize(width: 248, height: 295)
        )
        XCTAssertEqual(
            PetPanelMetrics.size(petSize: 140, isExpanded: true, hasCompletion: false),
            NSSize(width: 288, height: 477)
        )
        XCTAssertEqual(
            PetPanelMetrics.size(petSize: 140, isExpanded: false, hasCompletion: true),
            NSSize(width: 288, height: 367)
        )
    }

    func testFloatingFocusPanelUsesExplicitSizesForEveryPage() {
        XCTAssertEqual(FloatingFocusPanelMetrics.width, 270)
        XCTAssertEqual(FloatingFocusPanelMetrics.compactHeight, 176)
        XCTAssertEqual(FloatingFocusPanelMetrics.quickAddHeight, 210)
        XCTAssertEqual(FloatingFocusPanelMetrics.todayPlanHeight, 250)
    }

    func testFloatingPanelPlacementRecoversOffscreenFrames() {
        let visible = NSRect(x: 0, y: 46, width: 1512, height: 884)
        let offscreenPet = NSRect(x: 372, y: -961, width: 248, height: 295)
        let recovered = FloatingPanelPlacement.clamped(offscreenPet, to: visible)

        XCTAssertEqual(recovered.origin.x, 372)
        XCTAssertEqual(recovered.origin.y, visible.minY)
        XCTAssertTrue(visible.contains(recovered))
    }

    func testFloatingPanelPlacementHandlesPanelsLargerThanVisibleFrame() {
        let visible = NSRect(x: 100, y: 80, width: 200, height: 160)
        let oversized = NSRect(x: -500, y: 900, width: 260, height: 220)
        let recovered = FloatingPanelPlacement.clamped(oversized, to: visible)

        XCTAssertEqual(recovered.origin, visible.origin)
    }

    func testPetPoseScaleCompensatesForVisibleInkDensity() {
        XCTAssertEqual(
            PetVisualMetrics.perceivedPoseScale(
                opaquePixelCount: 6_400,
                croppedSize: CGSize(width: 100, height: 100)
            ),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PetVisualMetrics.perceivedPoseScale(
                opaquePixelCount: 4_000,
                croppedSize: CGSize(width: 100, height: 100)
            ),
            1.25,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PetVisualMetrics.perceivedPoseScale(
                opaquePixelCount: 9_000,
                croppedSize: CGSize(width: 100, height: 100)
            ),
            0.92,
            accuracy: 0.001
        )
    }

    @MainActor
    func testFloatingPanelKeepsMouseDownCoordinateWhenContentShrinks() {
        let reminderButtonLocation = NSPoint(x: 120, y: 286)
        let postCollapseMouseUpLocation = NSPoint(x: 120, y: 74)

        XCTAssertEqual(
            FloatingPanel.resolvedClickLocation(
                mouseDown: reminderButtonLocation,
                mouseUp: postCollapseMouseUpLocation
            ),
            reminderButtonLocation
        )
    }

    @MainActor
    func testFloatingPanelRejectsImplicitSwiftUIResize() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 40, y: 40, width: 288, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.setFrame(NSRect(x: 40, y: 40, width: 288, height: 1_530), display: false)
        XCTAssertEqual(panel.frame.size, NSSize(width: 288, height: 320))

        panel.isProgrammaticMove = true
        panel.setFrame(NSRect(x: 40, y: 40, width: 300, height: 360), display: false)
        XCTAssertEqual(panel.frame.size, NSSize(width: 300, height: 360))
    }

    func testIndependentTimerPanelIncludesEffectSafeArea() {
        XCTAssertEqual(FloatingTimerPanelMetrics.independentContentInset, 14)
        XCTAssertEqual(
            FloatingTimerPanelMetrics.independentSize(for: .progressRing),
            NSSize(width: 112, height: 112)
        )
        XCTAssertEqual(
            FloatingTimerPanelMetrics.independentSize(for: .tomato),
            NSSize(width: 112, height: 112)
        )
        XCTAssertEqual(
            FloatingTimerPanelMetrics.independentSize(for: .hourglass),
            NSSize(width: 112, height: 112)
        )
        XCTAssertEqual(
            FloatingTimerPanelMetrics.independentSize(for: .digital),
            NSSize(width: 148, height: 112)
        )
    }

    func testIndependentReminderPanelFitsItsCompactCard() {
        XCTAssertEqual(FloatingReminderPanelMetrics.contentSize, NSSize(width: 208, height: 80))
        XCTAssertEqual(FloatingReminderPanelMetrics.contentInset, 4)
        XCTAssertEqual(FloatingReminderPanelMetrics.panelSize, NSSize(width: 216, height: 88))
    }

    func testGenericMainWindowOpenReturnsToFocus() {
        XCTAssertEqual(MainWindowSectionPolicy.destination(for: nil), .focus)
        XCTAssertEqual(MainWindowSectionPolicy.destination(for: .reminders), .reminders)
        XCTAssertEqual(MainWindowSectionPolicy.destination(for: .settings), .settings)
    }

    func testAllThirtyEightPetAssetsKeepAControlledCountdownGap() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetRoot = projectRoot
            .appendingPathComponent("Sources/Resources/PetAssets", isDirectory: true)
        let urls = try FileManager.default
            .subpathsOfDirectory(atPath: assetRoot.path)
            .filter { $0.hasSuffix(".png") }
            .map { assetRoot.appendingPathComponent($0) }

        XCTAssertEqual(urls.count, 38)

        for url in urls {
            let image = try XCTUnwrap(NSImage(contentsOf: url), url.lastPathComponent)
            let asset = image.normalizedPetRaster()

            for size: CGFloat in [88, 140, 220] {
                for breath: CGFloat in [0.97, 1.03] {
                    for angle: Double in [-6, 0, 6] {
                        let top = PetVisualMetrics.visibleTopExtent(
                            imageSize: asset.image.size,
                            settingSize: size,
                            perceivedScale: asset.perceivedScale,
                            horizontalScale: 2 - breath,
                            verticalScale: breath,
                            rotationDegrees: angle
                        )
                        let offset = PetVisualMetrics.countdownBoardOffset(
                            for: size,
                            visibleTopExtent: top
                        )
                        let actualGap = offset - top - 6

                        XCTAssertGreaterThanOrEqual(
                            actualGap,
                            11.999,
                            "\(url.lastPathComponent) is too close at \(size) pt"
                        )
                        XCTAssertLessThanOrEqual(
                            actualGap,
                            18.001,
                            "\(url.lastPathComponent) is too far at \(size) pt"
                        )
                    }
                }
            }
        }
    }
}
