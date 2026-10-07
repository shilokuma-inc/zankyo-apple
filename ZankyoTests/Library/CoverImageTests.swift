import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Zankyo

nonisolated struct CoverImageTests {
    @Test
    func downscalesLargeCover() throws {
        let image = try #require(CoverImage.decode(try TestImage.make(width: 1024, height: 768)))

        #expect(image.width == CoverImage.maxPixelSize)
        #expect(image.height == 384)
    }

    @Test
    func keepsSmallJPEGAsIs() throws {
        let image = try #require(CoverImage.decode(try TestImage.make(width: 200, height: 100, type: .jpeg)))

        #expect(image.width == 200)
        #expect(image.height == 100)
    }

    @Test
    func rejectsUnsupportedFormat() throws {
        #expect(CoverImage.decode(try TestImage.make(width: 16, height: 16, type: .gif)) == nil)
        #expect(CoverImage.decode(try TestImage.make(width: 16, height: 16, type: .tiff)) == nil)
    }

    @Test
    func rejectsBrokenOrEmptyData() {
        #expect(CoverImage.decode(Data()) == nil)
        #expect(CoverImage.decode(Data("not an image".utf8)) == nil)
    }

    @Test
    func rejectsTooManyPixels() throws {
        #expect(CoverImage.decode(try TestImage.make(width: CoverImage.maxSourcePixels + 1, height: 1)) == nil)
    }
}
