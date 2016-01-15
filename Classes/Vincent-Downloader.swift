//
//  Vincent-Downloader.swift
//  Pods
//
//  Created by Kai Straßmann on 04.01.16.
//
//

import Foundation
import UIKit

public class Request {
    private(set) var trustsAllCertificates = false
    private(set) var credentials: NSURLCredential?
    private(set) var request: NSMutableURLRequest
    private(set) var completionClosure: ((url: NSURL?, error: NSError?, invalidated: Bool) -> ())?
    private(set) var identifier = NSUUID().UUIDString
    weak var downloadTask: NSURLSessionDownloadTask?
    var invalidated = false
    
    init(url: NSURL, cachePolicy: NSURLRequestCachePolicy, timeoutInterval: NSTimeInterval) {
        self.request = NSMutableURLRequest(URL: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        self.request.HTTPMethod = "GET"
    }
    
    // MARK: - Public Methods
    public func method(method: String) -> Request {
        request.HTTPMethod = method
        return self
    }
    
    public func credentials(urlCredentials: NSURLCredential?) -> Request {
        if let urlCredentials = urlCredentials, user = urlCredentials.user, password = urlCredentials.password {
            return credentials(user: user, password: password)
        } else {
            return self
        }
    }
    
    public func credentials(user user: String, password: String) -> Request {
        let userPasswordString = "\(user):\(password)"
        let userPasswordData = userPasswordString.dataUsingEncoding(NSUTF8StringEncoding)
        let base64EncodedCredential = userPasswordData!.base64EncodedStringWithOptions([])
        let authString = "Basic \(base64EncodedCredential)"
        header("Authorization", withValue: authString)
        return self
    }
    
    public func trustAllCertificates() -> Request {
        print("Vincent: WARNING! certificate validation is disabled!")
        trustsAllCertificates = true
        return self
    }
    
    public func header(header: String, withValue value: String) -> Request {
        request.setValue(value, forHTTPHeaderField: header)
        return self
    }
    
    func completion(completion: (url: NSURL?, error: NSError?, invalidated: Bool) -> ()) -> Request {
        completionClosure = completion
        return self
    }
    
    // MARK: - Private methods
    private func handleFinishedDownload(url: NSURL) {
        if let completionClosure = completionClosure {
            dispatch_sync(dispatch_get_main_queue()) {
                completionClosure(url: url, error: nil, invalidated: self.invalidated)
            }
        }
    }
    
    private func handleError(error: NSError) {
        print(error)
        if let completionClosure = completionClosure {
            dispatch_sync(dispatch_get_main_queue()) {
                completionClosure(url: nil, error: error, invalidated: self.invalidated)
            }
        }
    }
}

// MARK: -

class VincentDowloader: NSObject, NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, NSURLSessionDownloadDelegate {
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