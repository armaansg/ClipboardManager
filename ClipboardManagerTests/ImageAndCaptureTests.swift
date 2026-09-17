import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import ClipboardManager

final class ImageProcessorTests: XCTestCase {
    func testLargeOpaqueImageIsDownscaledToJPEG() throws {
        let processed = try XCTUnwrap(ImageProcessor.process(TestSupport.pngData(width: 3000, height: 1500, transparent: false)))
        XCTAssertEqual(processed.width, 2048)
        XCTAssertEqual(processed.height, 1024)
        XCTAssertEqual(processed.fileExtension, "jpg")
        XCTAssertEqual(processed.uti, UTType.jpeg.identifier)
        let thumb = try XCTUnwrap(ImageProcessor.dimensions(of: processed.thumbnail))
        XCTAssertLessThanOrEqual(max(thumb.0, thumb.1), 256)
    }

    func testTransparentImageStaysPNG() throws {
        let processed = try XCTUnwrap(ImageProcessor.process(TestSupport.pngData(width: 300, height: 300, transparent: true)))
        XCTAssertEqual(processed.fileExtension, "png")
        XCTAssertEqual(processed.width, 300)
        XCTAssertTrue(ImageProcessor.hasTransparentPixels(CGImageSourceCreateImageAtIndex(
            CGImageSourceCreateWithData(processed.data as CFData, nil)!, 0, nil)!))
    }

    func testSmallImageIsNotUpscaled() throws {
        let processed = try XCTUnwrap(ImageProcessor.process(TestSupport.pngData(width: 40, height: 20, transparent: false)))
        XCTAssertEqual(processed.width, 40)
        XCTAssertEqual(processed.height, 20)
    }

    func testGarbageDataReturnsNil() {
        XCTAssertNil(ImageProcessor.process(Data("not an image".utf8)))
    }
}

final class CaptureProcessorTests: XCTestCase {
    private var blobs: BlobStore!

    override func setUpWithError() throws {
        blobs = try BlobStore(directory: TestSupport.temporaryDirectory())
    }

    private func item(for content: CapturedContent, hash: Data = Data("x".utf8)) -> ClipItem? {
        CaptureProcessor.makeItem(from: CapturedPayload(content: content, hashInput: hash),
                                  source: SourceApp(bundleID: "com.example.app", name: "Example"), blobs: blobs)
    }

    func testTextItemFields() throws {
        let text = "\n\nleading newlines trimmed in preview"
        let item = try XCTUnwrap(item(for: .text(text, rtf: nil, isRich: false)))
        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.content, text)
        XCTAssertEqual(item.previewText, "leading newlines trimmed in preview")
        XCTAssertEqual(item.sourceAppName, "Example")
        XCTAssertEqual(item.byteSize, Int64(text.utf8.count))
        XCTAssertNil(item.blobPath)
    }

    func testRichTextWritesRTFBlob() throws {
        let rtf = Data("{\\rtf1 hi}".utf8)
        let item = try XCTUnwrap(item(for: .text("hi", rtf: rtf, isRich: true)))
        XCTAssertTrue(item.isRich)
        XCTAssertEqual(blobs.data(for: item.blobPath), rtf)
        XCTAssertEqual(item.byteSize, Int64(2 + rtf.count))
    }

    func testOversizedTextIsRejected() {
        let huge = String(repeating: "a", count: Int(AppConfig.maxItemBytes) + 1)
        XCTAssertNil(item(for: .text(huge, rtf: nil, isRich: false)))
    }

    func testImageItemWritesBlobAndThumbnail() throws {
        let png = TestSupport.pngData(width: 640, height: 480, transparent: false)
        let item = try XCTUnwrap(item(for: .image(png, uti: UTType.png.identifier), hash: png))
        XCTAssertEqual(item.type, .image)
        XCTAssertEqual(item.imageWidth, 640)
        XCTAssertEqual(item.previewText, "640 × 480")
        XCTAssertNotNil(blobs.data(for: item.blobPath))
        XCTAssertNotNil(blobs.data(for: item.thumbPath))
        XCTAssertEqual(item.byteSize, Int64((blobs.data(for: item.blobPath)?.count ?? 0) + (blobs.data(for: item.thumbPath)?.count ?? 0)))
    }

    func testFileItemCountsOnlyItsReference() throws {
        let urls = [URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/etc/passwd")]
        let item = try XCTUnwrap(item(for: .files(urls)))
        XCTAssertEqual(item.type, .file)
        XCTAssertEqual(item.filePaths, ["/etc/hosts", "/etc/passwd"])
        XCTAssertEqual(item.title, "hosts")
        XCTAssertEqual(item.byteSize, Int64(item.content.utf8.count))
        XCTAssertLessThan(item.byteSize, 200)
    }

    func testLinkItem() throws {
        let url = URL(string: "https://example.com/a")!
        let item = try XCTUnwrap(item(for: .link(url, title: "Example")))
        XCTAssertEqual(item.type, .link)
        XCTAssertEqual(item.url, url)
        XCTAssertEqual(item.title, "Example")
    }

    func testSHA256IsHex64() {
        let digest = CaptureProcessor.sha256(Data("abc".utf8))
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
