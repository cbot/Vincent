//
//  Vincent-Request.swift
//  Pods
//
//  Created by Privat on 24.05.16.
//
//

import UIKit

public class DownloadRequest {
    private(set) var trustsAllCertificates = false
    private(set) var credentials: URLCredential?
    private(set) var request: URLRequest
    private(set) var completionClosure: ((url: URL?, error: NSError?, invalidated: Bool) -> ())?
    private(set) var identifier = UUID().uuidString
    weak var downloadTask: URLSessionDownloadTask?
    var invalidated = false
    private(set) var fingerPrint = UUID().uuidString
    
    init(url: URL, cachePolicy: NSURLRequest.CachePolicy, timeoutInterval: TimeInterval) {
        self.request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        self.request.httpMethod = "GET"
        
        fingerPrint = url.absoluteString
    }
    
    // MARK: - Public Methods
    @discardableResult
    public func method(_ method: String) -> DownloadRequest {
        request.httpMethod = method
        return self
    }
    
    @discardableResult
    public func credentials(_ urlCredentials: URLCredential?) -> DownloadRequest {
        if let urlCredentials = urlCredentials, let user = urlCredentials.user, let password = urlCredentials.password {
            return credentials(user: user, password: password)
        } else {
            return self
        }
    }
    
    @discardableResult
    public func credentials(user: String, password: String) -> DownloadRequest {
        let userPasswordString = "\(user):\(password)"
        let userPasswordData = userPasswordString.data(using: String.Encoding.utf8)
        let base64EncodedCredential = userPasswordData!.base64EncodedString(options: [])
        let authString = "Basic \(base64EncodedCredential)"
        header("Authorization", withValue: authString)
        return self
    }
    
    @discardableResult
    public func trustAllCertificates() -> DownloadRequest {
        print("Vincent: WARNING! certificate validation is disabled!")
        trustsAllCertificates = true
        return self
    }
    
    @discardableResult
    public func header(_ header: String, withValue value: String) -> DownloadRequest {
        request.setValue(value, forHTTPHeaderField: header)
        return self
    }
    
    func setCustomIdentifier(_ identifier: String) {
        self.identifier = identifier
    }
    
    @discardableResult
    func completion(_ completion: (url: URL?, error: NSError?, invalidated: Bool) -> ()) -> DownloadRequest {
        completionClosure = completion
        return self
    }
    
    // MARK: - Private methods
    func handleFinishedDownload(_ url: URL) {
        if let completionClosure = completionClosure {
            DispatchQueue.main.sync {
                completionClosure(url: url, error: nil, invalidated: self.invalidated)
            }
        }
    }
    
    func handleError(_ error: NSError) {
        if error.code != -999 {
            print(error)
        }
        
        if let completionClosure = completionClosure {
            DispatchQueue.main.sync {
                completionClosure(url: nil, error: error, invalidated: self.invalidated)
            }
        }
    }
}
