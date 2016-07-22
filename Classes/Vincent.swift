//
//  Vincent.swift
//
//  Created by Kai Straßmann

import UIKit
import CryptoSwift

/// A completion closure type that is used throughout this library
public typealias CompletionClosure = (image: UIImage?, error: NSError?) -> Void

/// A closure type that allows the modification of a Request object
public typealias RequestModificationClosure = (request: DownloadRequest) -> Void

/**
 The different kind of options for cache handling when making requests
 
 - Automatic:     If a non stale image is contained in the cache, it is used. otherwise Protocol cache type is used
 - ForceCache:    if the image is contained in the cache (no matter how old), it is used. otherwise Protocol cache type is used
 - ForceDownload: ALWAYS creates a download task, ignores any cache headers from the server
 - Protocol:      ALWAYS creates a download task, cache headers decide if a request is actually made
 */
@objc public enum CacheType: Int {
    case automatic
    case forceCache
    case forceDownload
    case `protocol`
}

/// The main Vincent class that handles downloading and caching
@objc public class Vincent : NSObject {
    /// The shared instance of Vincent. This is for convenience, you are free to create additional instances as needed
    public static let sharedInstance = Vincent(identifier: "shared-downloader")
    
    /// A ready to use prefetcher instance
    public lazy var prefetcher: Prefetcher = Prefetcher(vincent: self)

    /// Whether to use the disk cache or memory-only caching. The default value is true, which enables the disk cache.
    public var useDiskCache = true
    
    /// The timeout interval to use when downloading images
    public var timeoutInterval = 30.0
    
    /// The amount of time after which a cached image is considered stale. The default value is 1 day.
    public var cacheInvalidationTimeout: TimeInterval = 1 * 24 * 3600
    
    /// The amount of memory to use for the memory cache
    public var memoryCacheSize: Int = 64 * 1024 * 1024 {
        willSet {
            memoryCache.totalCostLimit = newValue
        }
    }

    private var downloader = Dowloader()

    private(set) var diskCacheFolderUrl: URL
    
    private lazy var memoryCache: Cache<NSString, VincentCacheEntry> = {
        var cache = Cache<NSString, VincentCacheEntry>()
        cache.totalCostLimit = self.memoryCacheSize
        return cache
    }()
    
    private lazy var keyCache: Cache<NSString, NSString> = {
        var cache = Cache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()
    
    private var diskCacheSemaphore = DispatchSemaphore(value: 1);
    private var globalRequestHeaders = VincentGlobalHeaders()
    private var globalCredentials = VincentGlobalCredentials()
    private var trustsAllCertificates = false
    
    // MARK: - Constructor
    /**
    Creates a new Vincent instance with the given identifier.
    
    - parameter identifier: The identifier for this instance. This is used for disk caching.
    */
    public init(identifier: String) {
        let cachesDirectory = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
        diskCacheFolderUrl = try! URL(fileURLWithPath: cachesDirectory).appendingPathComponent(identifier, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: diskCacheFolderUrl, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Vincent: unable to create disk cache folder: \(error)")
        }
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(_:)), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
    }
    
    // MARK: - Public methods
    /**
    The method that does the actual download and cache handling.
    
    - parameter url:                 The URL to download from
    - parameter cacheType:           The CacheType to use for the download
    - parameter callErrorOnCancel:   Whether or not to call the completion block with an error for canceled requests. Defaults to false.
    - parameter requestDoneBlock:    An optional block that is guaranteed to be called after an image has been retrieved (from the cache or from the web) or when a requests has failed.
    - parameter requestModification: An optional block that allows the Request for to be modified.
    - parameter completion:          An optional completion closure that is called with either the retrieved image or with an instance of NSError.
    
    - returns: A request identifier that can be used to cancel the request
    */
    @discardableResult
    public func downloadImageFromUrl(_ url: URL, cacheType: CacheType, callErrorOnCancel: Bool = false, requestDone requestDoneBlock: (() -> ())? = nil, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) -> String {
        
        let identifier = UUID().uuidString
        let cacheKey = transformUrlToCacheKey(url.absoluteString!)
        
        let action = { (image: UIImage?) in
            if image != nil {
                requestDoneBlock?()
                completion?(image: image, error: nil)
                return
            } else if url.isFileURL {
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    self.cacheImage(image, key: cacheKey, tempImageFile: url, memCacheOnly: true)
                    requestDoneBlock?()
                    completion?(image: image, error: nil)
                } else {
                    requestDoneBlock?()
                    completion?(image: nil, error: NSError(domain: "Vincent", code: -6, userInfo: [NSLocalizedDescriptionKey: "unable to load image from file url"]))
                }
                return
            } else {
                let request = self.downloader.request(url, cachePolicy: cacheType == .forceDownload ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: self.timeoutInterval)
                request.setCustomIdentifier(identifier)
                request.header("Accept", withValue: "image/*, */*; q=0.5")
                for (key, value) in self.globalRequestHeaders.headersForHost(url.host) {
                    request.header(key, withValue: value)
                }
                
                if let credentials = self.globalCredentials.credentialsForHost(url.host), let user = credentials.user, let password = credentials.password {
                    request.credentials(user: user, password: password)
                }
                
                if self.trustsAllCertificates {
                    request.trustAllCertificates()
                }
                
                requestModification?(request: request)
                
                request.completion { [weak self] tmpImageUrl, error, invalidated in
                    if let this = self {
                        requestDoneBlock?()
                        
                        if let error = error {
                            if error.code == -999 && !callErrorOnCancel { // cancelled request
                                return
                            } else {
                                completion?(image: nil, error: error)
                            }
                        } else {
                            guard let tmpImageUrl = tmpImageUrl, let data = try? Data(contentsOf: tmpImageUrl) else {
                                completion?(image: nil, error: error ?? NSError(domain: "Vincent", code: -3, userInfo: [NSLocalizedDescriptionKey: "download error"]))
                                return
                            }
                            
                            if let image = UIImage(data: data) {
                                this.cacheImage(image, key: cacheKey, tempImageFile: tmpImageUrl, memCacheOnly: false)
                                if (!invalidated) {
                                    completion?(image: image, error: nil)
                                }
                            } else if (!invalidated) {
                                let error = NSError(domain: "Vincent", code: -2, userInfo:[NSLocalizedDescriptionKey: "unable to decode image"])
                                print(error)
                                completion?(image: nil, error: error)
                            }
                        }
                    }
                }
                
                self.downloader.executeRequest(request)
            }
        }
        
        if cacheType == .forceCache {
            retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true, completion: { image in
                action(image)
            })
        } else if cacheType == .automatic {
            retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: false, completion: { image in
                action(image)
            })
        } else {
            action(nil)
        }
        
        return identifier
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
    
    /**
     Stores an image in the cache
     
     - parameter imageData: the image data to store
     - parameter url:       the URL for this image, this is transformed and used as the cache key
     */
    public func storeImage(_ imageData: Data?, forUrl url: URL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString!)
            storeImage(imageData, forKey: cacheKey)
        }
    }
    
    /**
     Stores an image in the cache

     - parameter imageData: the image data to store
     - parameter key:       the cache key to use
     */
    public func storeImage(_ imageData: Data?, forKey key: String?) {
        if let cacheKey = key, let imageData = imageData, let image = UIImage(data: imageData), let tmpUrl = tmpFileWithData(imageData) {
            cacheImage(image, key: cacheKey, tempImageFile: tmpUrl, memCacheOnly: false)
        }
    }
    
    /**
     Fetches an image from the cache with the given cache key
     
     - parameter key: the cache key to use
     
     - returns: an instance of UIImage or nil
     */
    public func retrieveCachedImageForKey(_ key: String?) -> UIImage? {
        if let cacheKey = key {
            return retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        }
        return nil
    }
    
    public func retrieveCachedImageForKey(_ key: String?, completion: (image: UIImage?) -> ()) {
        if let cacheKey = key {
            retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true, completion: completion)
        } else {
            completion(image: nil)
        }
    }
    
    /**
     Fetches an image for the given URL from the cache
     
     - parameter url: the URL to fetch the image for
     
     - returns: an instance of UIImage or nil
     */
    public func retrieveCachedImageForUrl(_ url: URL?) -> UIImage? {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString!)
            return retrieveCachedImageForKey(cacheKey)
        }
        return nil
    }
    
    public func retrieveCachedImageForUrl(_ url: URL?, completion: (image: UIImage?) -> ()) {
        if let url = url {
            let cacheKey = self.transformUrlToCacheKey(url.absoluteString!)
            retrieveCachedImageForKey(cacheKey, completion: completion)
        } else {
            completion(image: nil)
        }
    }
    
    /**
     Deletes an image from the cache
     
     - parameter url: the URL for the image to be deleted
     */
    public func deleteCachedImageForUrl(_ url: URL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString!)
            deleteCachedImageForKey(cacheKey)
        }
    }
    
    /**
     Invalides a running download. An invalidated download is not canceled. Instead, the download continues in the background and the downloaded image is stored in the cache. However, no completion blocks are called.
     
     - parameter downloadIdentifier: the download identifier whose associated download should be invalidated
     */
    public func invalidate(_ downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.invalidateRequest(downloadIdentifier)
        }
    }
    
    /**
     Cancels a running download
     
     - parameter downloadIdentifier: the download identifier whose associated download should be canceled
     */
    public func cancel(_ downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.cancelRequest(downloadIdentifier)
        }
    }
    
    // MARK: - Caching
    private func cacheImage(_ image: UIImage, key: String, tempImageFile: URL, memCacheOnly: Bool) {
        var fileSize: Int
        
        if let path = tempImageFile.path {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                fileSize = (attributes[FileAttributeKey.size] as? NSNumber ?? 0).intValue
            } catch {
                fileSize = 0
            }
        } else {
            fileSize = 0
        }
        
        let cacheEntry = VincentCacheEntry(cacheKey: key, image: image, lastAccessed: Date(), fileSize: fileSize)
        
        // mem cache
        memoryCache.setObject(cacheEntry, forKey: key, cost: fileSize)
        
        // disk cache
        if useDiskCache && !memCacheOnly {
            saveCacheEntryToDisk(cacheEntry, tempImageFile: tempImageFile, forKey: key)
        }
    }
    
    private func retrieveCachedImageForKey(_ key: String?, ignoreLastAccessed: Bool, completion: (image: UIImage?) -> ()) {
        DispatchQueue.global(attributes: DispatchQueue.GlobalAttributes.qosDefault).async {
            let image = self.retrieveCachedImageForKey(key, ignoreLastAccessed: ignoreLastAccessed)
            
            DispatchQueue.main.async(execute: { 
                completion(image: image)
            })
        }
    }
    
    private func retrieveCachedImageForKey(_ key: String?, ignoreLastAccessed: Bool) -> UIImage? {
        if let key = key {
            var cacheEntry = memoryCache.object(forKey: key)
            
            if cacheEntry == nil && useDiskCache {
                cacheEntry = loadCacheEntryFromDiskForKey(key)
                
                if let cacheEntry = cacheEntry {
                    memoryCache.setObject(cacheEntry, forKey: key, cost: cacheEntry.fileSize)
                }
            }
            
            if let cacheEntry = cacheEntry, cacheEntry.lastAccessed.timeIntervalSince(Date()) < -cacheInvalidationTimeout {
                // stale
                deleteCachedImageForKey(key)
                return nil
            } else {
                cacheEntry?.lastAccessed = Date()
                if useDiskCache {
                    saveCacheEntryToDisk(cacheEntry, tempImageFile: nil, forKey: key)
                }
                return cacheEntry?.image
            }
        } else {
            return nil
        }
    }
    
    private func deleteCachedImageForKey(_ key: String?) {
        if let key = key {
            memoryCache.removeObject(forKey: key)
            if useDiskCache {
                saveCacheEntryToDisk(nil, tempImageFile: nil, forKey: key)
            }
        }
    }
    
    private func loadCacheEntryFromDiskForKey(_ key: String?) -> VincentCacheEntry? {
        if let key = key {
            let url = try! diskCacheFolderUrl.appendingPathComponent(key, isDirectory: false)
            if let path = url.path {
                let _ = self.diskCacheSemaphore.wait(timeout: DispatchTime.distantFuture)
                
                defer {
                    self.diskCacheSemaphore.signal()
                }
                
                if FileManager.default.fileExists(atPath: path) {
                    var lastAccess : AnyObject?
                    do {
                        try (url as NSURL).getResourceValue(&lastAccess, forKey: URLResourceKey.contentAccessDateKey)
                    } catch {
                        return nil
                    }
                    
                    if let lastAccess = lastAccess as? Date {
                        let image = UIImage(contentsOfFile: path)
                        if let image = image {
                            var fileSize = 0
                            do {
                                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                                fileSize = (attributes[FileAttributeKey.size] as? NSNumber ?? 0).intValue
                            } catch {
                                return nil
                            }
                            
                            let cacheEntry = VincentCacheEntry(cacheKey: key, image: image, lastAccessed: lastAccess, fileSize: fileSize)
                            return cacheEntry
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private func saveCacheEntryToDisk(_ cacheEntry: VincentCacheEntry?, tempImageFile: URL?, forKey key: String?) {
        guard let key = key else {return}
        
        let url = try! diskCacheFolderUrl.appendingPathComponent(key, isDirectory: false)
        
        let _ = self.diskCacheSemaphore.wait(timeout: DispatchTime.distantFuture);
        if let tempImageFile = tempImageFile, let path = url.path { // store new image
            if FileManager.default.fileExists(atPath: path) {
                let _ = try? FileManager.default.removeItem(at: url)
            }
            _ = try? FileManager.default.copyItem(at: tempImageFile, to: url)
        } else if let cacheEntry = cacheEntry { // update image access date
            _ = try? (url as NSURL).setResourceValue(cacheEntry.lastAccessed, forKey: URLResourceKey.contentAccessDateKey)
        } else { // delete image
            _ = try? FileManager.default.removeItem(at: url)
        }
        self.diskCacheSemaphore.signal()
    }
    
    // MARK: - Utility
    private func validateResponse(_ response: URLResponse?) throws {
        guard let response = response as? HTTPURLResponse else {
            throw NSError(domain: "Vincent", code: 1, userInfo: [NSLocalizedDescriptionKey: "unexpected response"])
        }
        
        if response.statusCode >= 400 {
            throw NSError(domain: "Vincent", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)])
        }
        
        if let mimeType = response.mimeType {
            if !mimeType.hasPrefix("image/") {
                throw NSError(domain: "Vincent", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid mime type"])
            }
        }
    }
    
    private func transformUrlToCacheKey(_ url: String) -> String {
        if let key = keyCache.object(forKey: url) as? String {
            return key
        } else {
            let key = url.md5()
            keyCache.setObject(key, forKey: url)
            return key
        }
    }
    
    private func tmpFileWithData(_ data: Data) -> URL? {
        let uuid = UUID().uuidString
        let tmpFileUrl = try! URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)
        if (try? data.write(to: tmpFileUrl, options: [.atomic])) != nil {
            return tmpFileUrl
        } else {
            return nil
        }
    }
    
    private func cleanup() {
        self.memoryCache.removeAllObjects()
        guard let path = diskCacheFolderUrl.path else {return}
        
        do {
            let filesArray = try FileManager.default.contentsOfDirectory(atPath: path)
            let now = Date()
            for file in filesArray {
                let url : URL = try! diskCacheFolderUrl.appendingPathComponent(file, isDirectory: false)
                var lastAccess : AnyObject?
                do {
                    try (url as NSURL).getResourceValue(&lastAccess, forKey: URLResourceKey.contentAccessDateKey)
                    if let lastAccess = lastAccess as? Date {
                        if (now.timeIntervalSince(lastAccess) > 30 * 24 * 3600) {
                            try FileManager.default.removeItem(at: url)
                        }
                    }
                } catch {
                    continue
                }
                
            }
        } catch {}
    }
    
    // MARK: - Notifications
    internal func appWillResignActive(_ notification: Notification) {
        cleanup()
    }
    
    // MARK: - Memory
    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanup()
    }
}

// MARK: - VincentCacheEntry
private class VincentCacheEntry: NSObject {
    var image : UIImage
    var lastAccessed : Date
    var cacheKey : String
    var fileSize : Int
    
    init(cacheKey: String, image: UIImage, lastAccessed: Date, fileSize: Int) {
        self.cacheKey = cacheKey
        self.image = image
        self.lastAccessed = lastAccessed
        self.fileSize = fileSize
        super.init()
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
