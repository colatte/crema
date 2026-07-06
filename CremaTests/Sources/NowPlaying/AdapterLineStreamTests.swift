import Testing
@testable import Crema

/// The byte→line splitting the adapter stream needs, tested with fake
/// bytes (the Perl process itself is manual-smoke). Covers chunk boundaries,
/// CRLF, empty lines, and EOF→finish.
struct AdapterLineStreamTests {

    // MARK: - LineBuffer (pure splitting)

    @Test func splitsMultipleLinesInOneChunkAndBuffersTheRemainder() {
        var buffer = AdapterLineStream.LineBuffer()
        #expect(buffer.push(Array("a\nb\nc".utf8)) == ["a", "b"])
        #expect(buffer.flush() == "c")
    }

    @Test func joinsALineSplitAcrossChunks() {
        var buffer = AdapterLineStream.LineBuffer()
        #expect(buffer.push(Array("hel".utf8)).isEmpty)
        #expect(buffer.push(Array("lo\n".utf8)) == ["hello"])
        #expect(buffer.flush() == nil)
    }

    @Test func dropsCarriageReturnBeforeNewline() {
        var buffer = AdapterLineStream.LineBuffer()
        #expect(buffer.push(Array("x\r\n".utf8)) == ["x"])
    }

    @Test func preservesEmptyLines() {
        var buffer = AdapterLineStream.LineBuffer()
        #expect(buffer.push(Array("\n".utf8)) == [""])
    }

    @Test func flushOnEmptyBufferIsNil() {
        var buffer = AdapterLineStream.LineBuffer()
        #expect(buffer.flush() == nil)
    }

    // MARK: - lines(from:) over an async byte sequence

    @Test func emitsLinesThenFinishesOnEOF() async {
        let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
        for byte in Array("one\ntwo\n".utf8) { continuation.yield(byte) }
        continuation.finish()

        var lines: [String] = []
        for await line in AdapterLineStream.lines(from: bytes) {
            lines.append(line)
        }
        #expect(lines == ["one", "two"])
    }

    @Test func emitsTrailingUnterminatedLineAtEOF() async {
        let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
        for byte in Array("{\"partial\":true}".utf8) { continuation.yield(byte) }
        continuation.finish()

        var lines: [String] = []
        for await line in AdapterLineStream.lines(from: bytes) {
            lines.append(line)
        }
        #expect(lines == ["{\"partial\":true}"])
    }

    @Test func emptyStreamFinishesWithNoLines() async {
        let (bytes, continuation) = AsyncStream<UInt8>.makeStream()
        continuation.finish()

        var lines: [String] = []
        for await line in AdapterLineStream.lines(from: bytes) {
            lines.append(line)
        }
        #expect(lines.isEmpty)
    }
}
