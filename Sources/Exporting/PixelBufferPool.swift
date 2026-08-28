import CoreVideo
import Foundation

public final class PixelBufferLease: @unchecked Sendable {
    public let buffer: CVPixelBuffer
    private let lock = NSLock()
    private var returnBuffer: ((CVPixelBuffer) -> Void)?

    fileprivate init(buffer: CVPixelBuffer, returnBuffer: @escaping (CVPixelBuffer) -> Void) {
        self.buffer = buffer
        self.returnBuffer = returnBuffer
    }

    public func release() {
        let action: ((CVPixelBuffer) -> Void)? = lock.withLock {
            defer { returnBuffer = nil }
            return returnBuffer
        }
        action?(buffer)
    }

    deinit { release() }
}

public final class PixelBufferPool: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let maximumBufferCount: Int

    private let lock = NSLock()
    private var available: [CVPixelBuffer] = []
    private var created = 0

    public init(width: Int, height: Int, maximumBufferCount: Int = 3) throws {
        guard width > 0, height > 0, maximumBufferCount > 0 else {
            throw MovieExportError.invalidPlan("Pixel buffer dimensions and count must be positive")
        }
        self.width = width
        self.height = height
        self.maximumBufferCount = maximumBufferCount
    }

    public var createdBufferCount: Int { lock.withLock { created } }

    public func acquire() -> PixelBufferLease? {
        lock.lock()
        let buffer: CVPixelBuffer?
        if let reusable = available.popLast() {
            buffer = reusable
        } else if created < maximumBufferCount {
            buffer = makeBuffer()
            if buffer != nil { created += 1 }
        } else {
            buffer = nil
        }
        lock.unlock()
        guard let buffer else { return nil }
        return PixelBufferLease(buffer: buffer) { [weak self] returned in
            self?.recycle(returned)
        }
    }

    private func recycle(_ buffer: CVPixelBuffer) {
        lock.withLock { available.append(buffer) }
    }

    private func makeBuffer() -> CVPixelBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        return status == kCVReturnSuccess ? buffer : nil
    }
}
