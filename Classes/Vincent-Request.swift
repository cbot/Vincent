//
//  Vincent-Request.swift
//  Pods
//
//  Created by Privat on 24.05.16.
//
//

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
    func handleFinishedDownload(url: NSURL) {
        if let completionClosure = completionClosure {
            dispatch_sync(dispatch_get_main_queue()) {
                completionClosure(url: url, error: nil, invalidated: self.invalidated)
            }
        }
    }
    
    func handleError(error: NSError) {
        if error.code != -999 {
            print(error)
        }
        
        if let completionClosure = completionClosure {
            dispatch_sync(dispatch_get_main_queue()) {
                completionClosure(url: nil, error: error, invalidated: self.invalidated)
            }
        }
    }
}