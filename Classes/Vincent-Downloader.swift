//
//  Vincent-Downloader.swift
//  Pods
//
//  Created by Kai Straßmann on 04.01.16.
//
//

import Foundation
import UIKit

class Dowloader: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
    private var registeredRequests = [String: Request]()
    
    private lazy var urlSession: NSURLSession = {
        let configuration =  NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPMaximumConnectionsPerHost = 10
        configuration.HTTPShouldUsePipelining = true
        return NSURLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    func request(url: NSURL, cachePolicy: NSURLRequestCachePolicy, timeoutInterval: NSTimeInterval) -> Request {
        return Request(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
    }
    
    func executeRequest(request: Request) {
        registeredRequests[request.identifier] = request
        
        if let task = existingTaskWithFingerPrint(request.fingerPrint) {
            task.identifiers.insert(request.identifier)
            request.downloadTask = task
        } else {
            let task = urlSession.downloadTaskWithRequest(request.request)
            task.identifiers.insert(request.identifier)
            task.fingerPrint = request.fingerPrint
            request.downloadTask = task
            task.resume()
        }
    }
    
    func existingTaskWithFingerPrint(fingerPrint: String) -> NSURLSessionDownloadTask? {
        let allTasks = registeredRequests.values.flatMap({ $0.downloadTask })
        return allTasks.filter({ $0.state == .Running && $0.fingerPrint == fingerPrint}).first
    }
    
    func invalidateRequest(identifier: String) {
        if let request = registeredRequests[identifier] {
            request.invalidated = true
        }
    }
    
    func cancelRequest(identifier: String) {
        invalidateRequest(identifier)
        
        if let request = registeredRequests[identifier], downloadTask = request.downloadTask {
            downloadTask.identifiers.remove(identifier)
            if downloadTask.identifiers.isEmpty {
                downloadTask.cancel()
            }
        }
    }
    
    // MARK: - NSURLSessionDownloadDelegate
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        
        guard let response = downloadTask.response as? NSHTTPURLResponse else { return }
    
        for request in requestsForIdentifiers(downloadTask.identifiers) {
            registeredRequests.removeValueForKey(request.identifier)
            
            if response.statusCode < 200 || response.statusCode >= 300 {
                let customError = NSError(domain: "Vincent", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Status Code \(response.statusCode)"])
                request.handleError(customError)
            } else {
                request.handleFinishedDownload(location)
            }
        }
    }
    
    // MARK: - NSURLSessionTaskDelegate
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didCompleteWithError error: NSError?) {
        // only connection errors are handled here!
        
        for request in requestsForIdentifiers(task.identifiers) {
            if let error = error {
                registeredRequests.removeValueForKey(request.identifier)
                request.handleError(error)
            }
        }
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        if let request = requestsForIdentifiers(task.identifiers).first {
            if let serverTrust = challenge.protectionSpace.serverTrust where challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if request.trustsAllCertificates {
                    completionHandler(NSURLSessionAuthChallengeDisposition.UseCredential, NSURLCredential(forTrust: serverTrust))
                } else {
                    completionHandler(.PerformDefaultHandling, nil)
                }
            } else if let credentials = request.credentials {
                if let currentRequest = task.currentRequest where currentRequest.valueForHTTPHeaderField("Authorization") == nil {
                    completionHandler(.UseCredential, credentials)
                } else {
                    completionHandler(.PerformDefaultHandling, nil)
                }
            }
        } else {
            completionHandler(.PerformDefaultHandling, nil)
        }
    }
    
    // MARK: - Utility
    private func requestsForIdentifiers(identifiers: Set<String>) -> [Request] {
        return identifiers.flatMap({registeredRequests[$0]})
    }
}

private var identifiersKey: UInt8 = 0
private var fingerPrintKey: UInt8 = 0
extension NSURLSessionTask {
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