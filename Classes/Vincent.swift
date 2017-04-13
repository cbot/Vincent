import UIKit
import CryptoKit
import AsyncImageCache

public enum VincentDownloadCompletionType {
    case canceled
    case error(error: NSError)
    case success(image: UIImage, data: Data)
}

public enum VincentImageCompletionType {
    case canceledOrInvalidated
    case error(error: NSError)
    case image(image: UIImage)
}

/**
 The different kind of options for cache handling when making requests
 
 - automatic:     If a non stale image is contained in the cache, it is used. otherwise Protocol cache type is used
 - forceCache:    if the image is contained in the cache (no matter how old), it is used. otherwise Protocol cache type is used
 - forceDownload: ALWAYS creates a download task, ignores any cache headers from the server
 - orotocol:      ALWAYS creates a download task, cache headers decide if a request is actually made
 - fromCache:     NEVER creates a download task, only the cache is queried
 */
@objc public enum CacheType: Int {
    case automatic
    case forceCache
    case forceDownload
    case `protocol`
    case fromCache
}

/// The main Vincent class that handles downloading and caching
public class Vincent {
    /// The shared instance of Vincent. This is for convenience, you are free to create additional instances as needed
    public static let sharedInstance = Vincent(identifier: "default")
    
    /// The timeout interval to use when downloading images
    public var timeoutInterval = 30.0
    public var cacheStaleInterval = 30.0

    private let operationQueue = OperationQueue()
    public let cache: AsyncImageCache
    
    private lazy var keyCache: NSCache<NSString, NSString> = {
        var cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()
    
    private var globalRequestHeaders = VincentGlobalHeaders()
    private var globalCredentials = VincentGlobalCredentials()
    private var trustsAllCertificates = false
    
    // MARK: - Constructor
    /**
    Creates a new Vincent instance with the given identifier.
    
    - parameter identifier: The identifier for this instance. This is used for disk caching.
    */
    public init(identifier: String) {
        cache = try! AsyncImageCache(name: identifier)
    }
    
    // MARK: - Public methods
    @discardableResult
    public func downloadImage(fromUrl url: URL, cachePolicy: NSURLRequest.CachePolicy, requestModification: ((_ request: URLRequest) -> URLRequest)? = nil, customIdentifier: String? = nil, completion: ((_ result: VincentDownloadCompletionType, _ invalidated: Bool) -> ())?) -> String {
        
        let identifier: String = customIdentifier ?? UUID().uuidString
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval)
        
        // set headers
        request.addValue("image/*, */*; q=0.5", forHTTPHeaderField: "Accept")
        for (key, value) in globalRequestHeaders.headersForHost(url.host) {
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        if let closure = requestModification {
            request = closure(request)
        }
        
        let operation = VincentOperation(urlRequest: request, identifier: identifier, callbackQueue: DispatchQueue.main, downloadFinishedBlock: { operation, result in
            
            switch result {
            case .canceled:
                completion?(.canceled, operation.invalidated)
            case .error(let error):
                completion?(.error(error: error as NSError), operation.invalidated)
            case .success(let image, let data):
                completion?(.success(image: image, data: data), operation.invalidated)
            }
        })
        
        // configure operation
        if let credentials = globalCredentials.credentialsForHost(url.host) {
            operation.credentials  = credentials
        }
        operation.trustsAllCertificates = trustsAllCertificates
        
        operationQueue.addOperation(operation)
    
        return identifier
    }
    
    public func retrieveImage(fromUrl url: URL, cacheType: CacheType, requestModification: ((_ request: URLRequest) -> URLRequest)? = nil, customIdentifier: String? = nil, completion: ((_ result: VincentImageCompletionType) -> ())?) {
        let cacheKey = transformUrlToCacheKey(url)
        
        let downloadAction = { (cachePolicy: NSURLRequest.CachePolicy) -> Void in
            self.downloadImage(fromUrl: url, cachePolicy: cachePolicy, requestModification: requestModification, customIdentifier: customIdentifier, completion: { completionType, invalidated in
                
                if invalidated {
                    completion?(.canceledOrInvalidated)
                } else {
                    switch completionType {
                    case .canceled:
                        completion?(.canceledOrInvalidated)
                    case .error(let error):
                        completion?(.error(error: error))
                    case .success(let image, let data):
                        self.cache.store(data: data, forKey: cacheKey, image: image, callbackQueue: DispatchQueue.main, completion: { 
                            completion?(.image(image: image))
                        })
                    }
                }
            })
        }
        
        switch cacheType {
        case .forceDownload:
            downloadAction(.reloadIgnoringLocalCacheData)
        case .protocol:
            downloadAction(.useProtocolCachePolicy)
        default:
            cache.fetch(itemWithKey: cacheKey) { item in
                if let item = item {
                    if cacheType == .fromCache || cacheType == .forceCache || Date().timeIntervalSince(item.created) < self.cacheStaleInterval {
                        completion?(.image(image: item.image))
                    } else {
                        downloadAction(.useProtocolCachePolicy)
                    }
                } else {
                    if cacheType == .fromCache {
                        completion?(.canceledOrInvalidated)
                    } else {
                        downloadAction(.useProtocolCachePolicy)
                    }
                }
            }
        }
    }
    
    public func cancelDownload(identifier: String?) {
        guard let identifier = identifier else { return }
        
        for operation in operationQueue.operations {
            if let operation = operation as? VincentOperation, operation.identifier == identifier {
                operation.cancel()
            }
        }
    }
    
    public func invalidateDownload(identifier: String?) {
        guard let identifier = identifier else { return }
    
        for operation in operationQueue.operations {
            if let operation = operation as? VincentOperation, operation.identifier == identifier {
                operation.invalidated = true
            }
        }
    }
    
    /**
     Sets a global HTTP header to use for all requests. Use an RequestModificationClosure (see downloadImageFromUrl) to set headers for individual requests.
     
     - parameter value: the header's value. Pass nil to remove the header with the given name.
     - parameter name:  the header's name
     - parameter host:  if given, the header is only set for requests to the specific host
     */
    public func setGlobalHeaderValue(_ value: String?, forHeaderWithName name: String, forHost host: String? = nil) {
        globalRequestHeaders.setHeader(name, value: value, forHost: host)
    }
    
    /**
     Sets global HTTP Basic auth credentials for all requests. Use an RequestModificationClosure (see downloadImageFromUrl) to set credentials for individual requests.
     
     - parameter credentials: the credentials to be used. Pass nil to remove credentials.
     - parameter host:        if given, the credentials are only set for requests to the specific host
     */
    public func setGlobalBasicAuthCredentials(_ credentials: URLCredential?, forHost host: String? = nil) {
        globalCredentials.setCredentials(credentials, forHost: host)
    }
    
    /**
     Sets global HTTP Basic auth credentials for all requests. Use an RequestModificationClosure (see downloadImageFromUrl) to set credentials for individual requests.
     
     - parameter user:     the user name to be used. Pass nil to remove credentials.
     - parameter password: the password to be used. Pass nil to remove credentials.
     - parameter host:     if given, the credentials are only set for requests to the specific host
     */
    public func setGlobalBasicAuthCredentials(user: String?, password: String?, forHost host: String? = nil) {
        if let user = user, let password = password {
            globalCredentials.setCredentials(URLCredential(user: user, password: password, persistence: .none), forHost: host)
        } else {
            globalCredentials.setCredentials(nil, forHost: host)
        }
    }
    
    /**
     Disables HTTPS certificate validation for all requests. Be careful with this setting, this should only be used during development. On iOS 9 and later you have to make sure to also disable ATS in your info.plist.
     */
    public func trustAllCertificates() {
        trustsAllCertificates = true
    }
    
    private func transformUrlToCacheKey(_ url: URL) -> String {
        let urlString = url.absoluteString
        
        if let key = keyCache.object(forKey: urlString as NSString) as String? {
            return key
        } else {
            if let data = urlString.data(using: .utf8) {
                return data.digest(using: .md5).hexString
            } else {
                return ""
            }
        }
    }
}

// MARK: - VincentGlobalHeaders
private class VincentGlobalHeaders {
    private var allHostsHeaders = [String: String]()
    private var specificHostHeaders = [String: [String: String]]()
    
    func setHeader(_ name: String, value: String?, forHost host: String?) {
        if let host = host {
            var headers = specificHostHeaders[host] ?? [String: String]()
            headers[name] = value
            specificHostHeaders[host] = headers
        } else {
            allHostsHeaders[name] = value
        }
    }
    
    func setHeaders(_ headers: [String: String], forHost host: String?) {
        if let host = host {
            specificHostHeaders[host] = headers
        } else {
            allHostsHeaders = headers
        }
    }
    
    func headersForHost(_ host: String?) -> [String: String] {
        if let host = host {
            if let specificHeaders = specificHostHeaders[host] {
                return specificHeaders.reduce(allHostsHeaders) { (dict, e) in
                    var mutableDict = dict
                    mutableDict[e.0] = e.1
                    return mutableDict
                }
            } else {
                return allHostsHeaders
            }
        } else {
            return allHostsHeaders
        }
    }
}

// MARK: - VincentGlobalCredentials
private class VincentGlobalCredentials {
    private var allHostsCredentials: URLCredential?
    private var specificHostCredentials = [String: URLCredential]()
    
    func setCredentials(_ credentials: URLCredential?, forHost host: String?) {
        if let host = host {
            specificHostCredentials[host] = credentials
        } else {
            allHostsCredentials = credentials
        }
    }
    
    func credentialsForHost(_ host: String?) -> URLCredential? {
        if let host = host {
            if let specificCredentials = specificHostCredentials[host] {
                return specificCredentials
            } else {
                return allHostsCredentials
            }
        } else {
            return allHostsCredentials
        }
    }
}

// MARK: - Data Extension
fileprivate extension Data {
    var hexString: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
}
