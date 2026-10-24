import CoreGraphics
import Testing
@testable import Crema

/// The Dock's room, read from a screen's frame and visible frame. The border
/// passes NSScreen's two rects straight in; what this pins is the arithmetic: the
/// right edge per edge and sign, and the screen's origin cancelling out.
struct ScreenGeometryTests {

    @Test func theDockAlongTheBottomKeepsRoomThereAlone() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // Measured: a 90 pt Dock, menu bar 34 pt (scripts/probes/dock-visible-frame.swift).
        let room = ScreenGeometry.dockRoom(frame: frame, visible: CGRect(x: 0, y: 90, width: 1512, height: 858))
        #expect(room.bottom == 90)
        #expect(room.left == 0)
        #expect(room.right == 0)
    }

    @Test func aSideDockKeepsRoomOnItsOwnSide() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = ScreenGeometry.dockRoom(frame: frame, visible: CGRect(x: 76, y: 0, width: 1436, height: 948))
        #expect(left.left == 76)
        #expect(left.right == 0)
        #expect(left.bottom == 0)
        let right = ScreenGeometry.dockRoom(frame: frame, visible: CGRect(x: 0, y: 0, width: 1436, height: 948))
        #expect(right.right == 76)
        #expect(right.left == 0)
    }

    @Test func aScreenAwayFromTheOriginReadsTheSameRoom() {
        // A secondary display left of and above the main one: global origins are
        // offset, negative included, and the room is the same as at the origin.
        let frame = CGRect(x: -1280, y: 400, width: 1280, height: 800)
        let room = ScreenGeometry.dockRoom(frame: frame, visible: CGRect(x: -1280, y: 470, width: 1210, height: 700))
        #expect(room.bottom == 70)
        #expect(room.left == 0)
        #expect(room.right == 70)
    }

    @Test func clearingTheDockLeavesEverythingElse() {
        let geometry = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32, auxLeft: 663.5, auxRight: 663.5, scale: 2,
            dockBottom: 90, dockLeft: 4, dockRight: 5
        )
        let cleared = geometry.withoutDock
        #expect(cleared.dockBottom == 0 && cleared.dockLeft == 0 && cleared.dockRight == 0)
        #expect(cleared.frame == geometry.frame)
        #expect(cleared.safeTop == geometry.safeTop)
        #expect(cleared.auxLeft == geometry.auxLeft && cleared.auxRight == geometry.auxRight)
        #expect(cleared.scale == geometry.scale)
    }
}
