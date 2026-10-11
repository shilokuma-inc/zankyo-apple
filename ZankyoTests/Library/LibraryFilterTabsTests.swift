import CoreGraphics
import Testing
@testable import Zankyo

struct LibraryFilterTabsTests {
    @Test
    func swipeLeftOpensTheNextTab() {
        #expect(LibraryFilterTabs.filter(after: .all, swipe: CGSize(width: -80, height: 4)) == .favorites)
        // 右端のタブより先は無い
        #expect(LibraryFilterTabs.filter(after: .favorites, swipe: CGSize(width: -80, height: 4)) == nil)
    }

    @Test
    func swipeRightOpensThePreviousTab() {
        #expect(LibraryFilterTabs.filter(after: .favorites, swipe: CGSize(width: 80, height: -4)) == .all)
        #expect(LibraryFilterTabs.filter(after: .all, swipe: CGSize(width: 80, height: -4)) == nil)
    }

    @Test
    func shortOrVerticalDragsDoNotSwitch() {
        // 少し動いただけや、一覧をスクロールしようとした縦の動きでは切り替えない
        let short = LibraryFilterTabs.swipeThreshold - 1
        #expect(LibraryFilterTabs.filter(after: .all, swipe: CGSize(width: -short, height: 0)) == nil)
        #expect(LibraryFilterTabs.filter(after: .all, swipe: CGSize(width: -60, height: 120)) == nil)
    }
}
