//
//  BaseOperation.swift
//  VWService
//
//  Created by Kai Straßmann on 06.11.15.
//  Copyright © 2015 Volkswagen AG. All rights reserved.
//

import Foundation

public enum VincentOperationResult {
    case successful(tmpUrl: URL)
    case failed(error: Error)
    case canceled
}

public typealias VincentOperationCompletionBlock = (_ operation: VincentOperation, _ result: VincentOperationResult) -> ()

public class VincentOperation: Operation, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    public var invalidated = false
    public var trustsAllCertificates = false
    public var credentials: URLCredential? = nil
    
    public let identifier: String
    
    // the request to be made
    private let urlRequest: URLRequest
    
    // a completion block
    private let finishedBlock: VincentOperationCompletionBlock
    
    // the urlsession to use for the request
    private weak var urlSession: URLSession?
    
    private var completionBlockIdentifiers = Set<String>()
    
    enum State {
        case ready, executing, finished
        func keyPath() -> String {
            switch self {
            case .ready:
                return "isReady"
            case .executing:
                return "isExecuting"
            case .finished:
                return "isFinished"
            }
        }
    }
    
    var state: State = State.ready {
        willSet {
            willChangeValue(forKey: newValue.keyPath())
            willChangeValue(forKey: state.keyPath())
        }
        didSet {
            didChangeValue(forKey: oldValue.keyPath())
            didChangeValue(forKey: state.keyPath())
        }
    }
    
    override public func start() {
        if isCancelled {
            state = .finished
        } else {
            state = .executing
            main()
        }
    }
    
    // MARK: - NSOperation
    override public var isReady: Bool {
        return super.isReady && state == .ready
    }
    
    override public var isExecuting: Bool {
        return state == .executing
    }
    
    override public var isFinished: Bool {
        return state == .finished
    }
    
    override public var isAsynchronous: Bool {
        return true
    }
    
    // MARK:
    public init(urlRequest request: URLRequest, identifier id: String, downloadFinishedBlock: @escaping VincentOperationCompletionBlock) {
        urlRequest = request
        identifier = id
        finishedBlock = downloadFinishedBlock
        super.init()
    }
    
    // MARK: - Entry point
    override public func main() {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 10
        configuration.httpShouldUsePipelining = true
        let urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.urlSession = urlSession
        let task = urlSession.downloadTask(with: urlRequest)
        task.resume()
    }
    
    // MARK: - NSURLSessionDownloadDelegate
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse else { return }
        
        if (200...299).contains(response.statusCode) {
            finishedBlock(self, .successful(tmpUrl: location))
        } else {
            finishedBlock(self, .failed(error: NSError(domain: "VincentOperation", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "unexepected status code \(response.statusCode)"])))
        }
    }
    
    // MARK: - NSURLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // only connection errors are handled here!
        if let error = error {
            finishedBlock(self, .failed(error: error))
        }
        
        state = .finished
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let serverTrust = challenge.protectionSpace.serverTrust, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if trustsAllCertificates {
                completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else if let credentials = credentials {
            if let currentRequest = task.currentRequest, currentRequest.value(forHTTPHeaderField: "Authorization") == nil {
                completionHandler(.useCredential, credentials)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Utility
    public override func cancel() {
        super.cancel()
        invalidated = true
        urlSession?.invalidateAndCancel()
        finishedBlock(self, .canceled)
        state = .finished
    }
    
    public func matches(urlRequest: URLRequest) -> Bool {
        return urlRequest.url != nil && self.urlRequest.url == urlRequest.url
    }
    
    func appendCompletionBlock(block: (() -> ())?) {
        guard let block = block else { return }
        
        if let completionBlock = completionBlock {
            self.completionBlock = {
                completionBlock()
                block()
            }
        } else {
            completionBlock = block
        }
    }
    
    // MARK: - Memory
    deinit {
        // we're done with our session
        urlSession?.invalidateAndCancel()
    }
}
