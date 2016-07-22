//
//  Vincent-Downloader.swift
//  Pods
//
//  Created by Kai Straßmann on 04.01.16.
//
//

import Foundation
import UIKit

class Dowloader: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDownloadDelegate {
    private var registeredRequests = [String: DownloadRequest]()
    
    private lazy var urlSession: Foundation.URLSession = {
        let configuration =  URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 10
        configuration.httpShouldUsePipelining = true
        return Foundation.URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    func request(_ url: URL, cachePolicy: NSURLRequest.CachePolicy, timeoutInterval: TimeInterval) -> DownloadRequest {
        return DownloadRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    }
    
    func executeRequest(_ request: DownloadRequest) {
        registeredRequests[request.identifier] = request
        
        if let task = existingTaskWithFingerPrint(request.fingerPrint) {
            task.identifiers.insert(request.identifier)
            request.downloadTask = task
        } else {
            let task = urlSession.downloadTask(with: request.request)
            task.identifiers.insert(request.identifier)
            task.fingerPrint = request.fingerPrint
            request.downloadTask = task
            task.resume()
        }
    }
    
    func existingTaskWithFingerPrint(_ fingerPrint: String) -> URLSessionDownloadTask? {
        let allTasks = registeredRequests.values.flatMap({ $0.downloadTask })
        return allTasks.filter({ $0.state == .running && $0.fingerPrint == fingerPrint}).first
    }
    
    func invalidateRequest(_ identifier: String) {
        if let request = registeredRequests[identifier] {
            request.invalidated = true
        }
    }
    
    func cancelRequest(_ identifier: String) {
        invalidateRequest(identifier)
        
        if let request = registeredRequests[identifier], let downloadTask = request.downloadTask {
            downloadTask.identifiers.remove(identifier)
            if downloadTask.identifiers.isEmpty {
                downloadTask.cancel()
            }
        }
    }
    
    // MARK: - NSURLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        guard let response = downloadTask.response as? HTTPURLResponse else { return }
    
        for request in requestsForIdentifiers(downloadTask.identifiers) {
            registeredRequests.removeValue(forKey: request.identifier)
            
            if response.statusCode < 200 || response.statusCode >= 300 {
                let customError = NSError(domain: "Vincent", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status Code \(response.statusCode)"])
                request.handleError(customError)
            } else {
                request.handleFinishedDownload(location)
            }
        }
    }
    
    // MARK: - NSURLSessionTaskDelegate
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: NSError?) {
        // only connection errors are handled here!
        
        for request in requestsForIdentifiers(task.identifiers) {
            if let error = error {
                registeredRequests.removeValue(forKey: request.identifier)
                request.handleError(error)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: (Foundation.URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let request = requestsForIdentifiers(task.identifiers).first {
            if let serverTrust = challenge.protectionSpace.serverTrust, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if request.trustsAllCertificates {
                    completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: serverTrust))
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            } else if let credentials = request.credentials {
                if let currentRequest = task.currentRequest, currentRequest.value(forHTTPHeaderField: "Authorization") == nil {
                    completionHandler(.useCredential, credentials)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    // MARK: - Utility
    private func requestsForIdentifiers(_ identifiers: Set<String>) -> [DownloadRequest] {
        return identifiers.flatMap({registeredRequests[$0]})
    }
}

private var identifiersKey: UInt8 = 0
private var fingerPrintKey: UInt8 = 0
extension URLSessionTask {
    var identifiers: Set<String> {
        get {
            return objc_getAssociatedObject(self, &identifiersKey) as? Set<String> ?? Set<String>()
        }
        set {
            objc_setAssociatedObject(self, &identifiersKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var fingerPrint: String {
        get {
            return objc_getAssociatedObject(self, &fingerPrintKey) as? String ?? ""
        }
        set {
            objc_setAssociatedObject(self, &fingerPrintKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
}
