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
        let task = urlSession.downloadTaskWithRequest(request.request)
        task.taskDescription = request.identifier
        request.downloadTask = task
        registeredRequests[request.identifier] = request
        task.resume()
    }
    
    func invalidateRequest(identifier: String) {
        if let request = requestForIdentifier(identifier) {
            request.invalidated = true
        }
    }
    
    func cancelRequest(identifier: String) {
        if let request = requestForIdentifier(identifier) {
            request.invalidated = true
            request.downloadTask?.cancel()
        }
    }
    
    // MARK: - NSURLSessionDownloadDelegate
    func URLSession(session: NSURLSession, downloadTask: NSURLSessionDownloadTask, didFinishDownloadingToURL location: NSURL) {
        if let request = requestForIdentifier(downloadTask.taskDescription), response = downloadTask.response as? NSHTTPURLResponse {
            
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
        if let request = requestForIdentifier(task.taskDescription) {
            
            if let error = error {
                registeredRequests.removeValueForKey(request.identifier)
                request.handleError(error)
            }
        }
    }
    
    func URLSession(session: NSURLSession, task: NSURLSessionTask, didReceiveChallenge challenge: NSURLAuthenticationChallenge, completionHandler: (NSURLSessionAuthChallengeDisposition, NSURLCredential?) -> Void) {
        if let request = requestForIdentifier(task.taskDescription) {
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
    private func requestForIdentifier(tag: String?) -> Request? {
        if let tag = tag {
            return registeredRequests[tag]
        } else {
            return nil
        }
    }
}