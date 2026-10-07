import Foundation
import Testing
@testable import Zankyo

nonisolated struct MapExtractorTests {
    @Test
    func extractsTopLevelFilesWithLowercasedNames() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try Self.write(
            [("Info.dat", Data("info".utf8)), ("ExpertPlus.dat", Data("notes".utf8)), ("song.egg", Data("audio".utf8))],
            in: directory
        )
        let destination = directory.appending(path: "Maps/map", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try MapExtractor.extract(zipAt: zip, to: destination)

        let names = try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)).sorted()
        #expect(names == ["expertplus.dat", "info.dat", "song.egg"])
        #expect(try Data(contentsOf: destination.appending(path: "expertplus.dat")) == Data("notes".utf8))
    }

    @Test
    func skipsNestedAndUnsafePaths() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try Self.write(
            [("Info.dat", Data("info".utf8)), ("../escape.dat", Data("x".utf8)), ("folder/inner.dat", Data("y".utf8))],
            in: directory
        )
        let destination = directory.appending(path: "Maps/map", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try MapExtractor.extract(zipAt: zip, to: destination)

        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)) == ["info.dat"])
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "Maps/escape.dat").path(percentEncoded: false)))
    }

    @Test
    func rejectsZipWithoutInfoAndLeavesNothing() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try Self.write([("readme.txt", Data("hello".utf8))], in: directory)
        let maps = directory.appending(path: "Maps", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: maps, withIntermediateDirectories: true)

        #expect(throws: MapArchiveError.invalidMap) {
            try MapExtractor.extract(zipAt: zip, to: maps.appending(path: "map"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: maps.path(percentEncoded: false)).isEmpty)
    }

    @Test
    func rejectsWhenTotalExceedsLimitAndLeavesNothing() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try Self.write([("Info.dat", Data("info".utf8)), ("song.egg", Data(count: 2_048))], in: directory)
        let maps = directory.appending(path: "Maps", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: maps, withIntermediateDirectories: true)

        #expect(throws: MapArchiveError.tooLarge) {
            try MapExtractor.extract(zipAt: zip, to: maps.appending(path: "map"), maxTotalBytes: 1_024)
        }
        // 一時フォルダも残さない
        #expect(try FileManager.default.contentsOfDirectory(atPath: maps.path(percentEncoded: false)).isEmpty)
    }

    @Test
    func replacesExistingFolder() throws {
        let directory = try TestFixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appending(path: "Maps/map", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "stale.dat"))
        let zip = try Self.write([("Info.dat", Data("info".utf8))], in: directory)

        try MapExtractor.extract(zipAt: zip, to: destination)

        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)) == ["info.dat"])
    }

    private static func write(_ files: [(String, Data)], in directory: URL) throws -> URL {
        let url = directory.appending(path: "map.zip", directoryHint: .notDirectory)
        try TestZip.make(files.map { (name: $0.0, data: $0.1) }).write(to: url)
        return url
    }
}
