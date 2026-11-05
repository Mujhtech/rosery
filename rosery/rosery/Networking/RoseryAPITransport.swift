import Foundation

/// All redirects are rejected, so assertion headers never follow another URL.
nonisolated final class RoseryAPIRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

nonisolated struct RoseryAPITransport: Sendable {
    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: configuration, delegate: RoseryAPIRedirectPolicy(),
                             delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        // Ending iteration alone need not stop an unfinished response. Explicitly
        // cancel on size rejection, cancellation, decoding exit, or completion.
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw RoseryAPIError.invalidResponse
        }
        guard response.expectedContentLength <= RoseryAPIProtocol.maximumResponseBytes else {
            throw RoseryAPIError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < RoseryAPIProtocol.maximumResponseBytes else {
                throw RoseryAPIError.responseTooLarge
            }
            data.append(byte)
        }
        return (data, response)
    }
}
