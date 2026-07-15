import Foundation

/// Intercepts URLSession traffic per host so provider clients can be tested
/// end-to-end (request building through response parsing) without a network.
/// Registered globally, so it also catches `URLSession.shared` — which is
/// what `DictationPipeline`'s providers use.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var body: Data
    }

    /// host → handler. Handlers receive the request with its body materialized.
    nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest, Data) -> Response] = [:]
    private static let lock = NSLock()

    static func stub(host: String, handler: @escaping @Sendable (URLRequest, Data) -> Response) {
        lock.withLock { handlers[host] = handler }
    }

    static func reset() {
        lock.withLock { handlers = [:] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.withLock { handlers[request.url?.host() ?? ""] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard let handler = Self.lock.withLock({ Self.handlers[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        // URLSession moves POST bodies into a stream before the protocol sees them.
        let body = request.httpBody ?? Self.drain(request.httpBodyStream)
        let response = handler(request, body)
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
