//
//  Vincent.swift
//
//  Created by Kai Straßmann

import UIKit
import CryptoSwift

/// A completion closure type that is used throughout this library
public typealias CompletionClosure = (image: UIImage?, error: NSError?) -> Void

/// A closure type that allows the modification of a Request object
public typealias RequestModificationClosure = (request: Request) -> Void

/**
 The different kind of options for cache handling when making requests
 
 - Automatic:     If a non stale image is contained in the cache, it is used. otherwise Protocol cache type is used
 - ForceCache:    if the image is contained in the cache (no matter how old), it is used. otherwise Protocol cache type is used
 - ForceDownload: ALWAYS creates a download task, ignores any cache headers from the server
 - Protocol:      ALWAYS creates a download task, cache headers decide if a request is actually made
 */
@objc public enum CacheType: Int {
    case Automatic
    case ForceCache
    case ForceDownload
    case Protocol
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
    public var cacheInvalidationTimeout: NSTimeInterval = 1 * 24 * 3600
    
    /// The amount of memory to use for the memory cache
    public var memoryCacheSize: Int = 64 * 1024 * 1024 {
        willSet {
            memoryCache.totalCostLimit = newValue
        }
    }

    private var downloader = Dowloader()

    private(set) var diskCacheFolderUrl: NSURL
    
    private lazy var memoryCache: NSCache = {
        var cache = NSCache()
        cache.totalCostLimit = self.memoryCacheSize
        return cache
    }()
    
    private lazy var keyCache: NSCache = {
        var cache = NSCache()
        cache.countLimit = 512
        return cache
    }()
    
    private var diskCacheSemaphore = dispatch_semaphore_create(1);
    private var globalRequestHeaders = VincentGlobalHeaders()
    private var globalCredentials = VincentGlobalCredentials()
    private var trustsAllCertificates = false
    
    // MARK: - Constructor
    /**
    Creates a new Vincent instance with the given identifier.
    
    - parameter identifier: The identifier for this instance. This is used for disk caching.
    */
    public init(identifier: String) {
        let cachesDirectory = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first!
        diskCacheFolderUrl = NSURL(fileURLWithPath: cachesDirectory).URLByAppendingPathComponent(identifier, isDirectory: false)
        do {
            try NSFileManager.defaultManager().createDirectoryAtURL(diskCacheFolderUrl, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Vincent: unable to create disk cache folder: \(error)")
        }
        super.init()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(appWillResignActive(_:)), name: UIApplicationWillResignActiveNotification, object: nil)
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
    public func downloadImageFromUrl(url: NSURL, cacheType: CacheType, callErrorOnCancel: Bool = false, requestDone requestDoneBlock: (() -> ())? = nil, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) -> String {
        
        let identifier = NSUUID().UUIDString
        let cacheKey = transformUrlToCacheKey(url.absoluteString)
        
        let action = { (image: UIImage?) in
            if image != nil {
                requestDoneBlock?()
                completion?(image: image, error: nil)
                return
            } else if url.fileURL {
                if let data = NSData(contentsOfURL: url), image = UIImage(data: data) {
                    self.cacheImage(image, key: cacheKey, tempImageFile: url, memCacheOnly: true)
                    requestDoneBlock?()
                    completion?(image: image, error: nil)
                } else {
                    requestDoneBlock?()
                    completion?(image: nil, error: NSError(domain: "Vincent", code: -6, userInfo: [NSLocalizedDescriptionKey: "unable to load image from file url"]))
                }
                return
            } else {
                let request = self.downloader.request(url, cachePolicy: cacheType == .ForceDownload ? .ReloadIgnoringLocalCacheData : .UseProtocolCachePolicy, timeoutInterval: self.timeoutInterval)
                request.setCustomIdentifier(identifier)
                request.header("Accept", withValue: "image/*, */*; q=0.5")
                for (key, value) in self.globalRequestHeaders.headersForHost(url.host) {
                    request.header(key, withValue: value)
                }
                
                if let credentials = self.globalCredentials.credentialsForHost(url.host), user = credentials.user, password = credentials.password {
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
                            guard let tmpImageUrl = tmpImageUrl, data = NSData(contentsOfURL: tmpImageUrl) else {
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
        
        if cacheType == .ForceCache {
            retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true, completion: { image in
                action(image)
            })
        } else if cacheType == .Automatic {
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
    public func setGlobalHeaderValue(value: String?, forHeaderWithName name: String, forHost host: String? = nil) {
        globalRequestHeaders.setHeader(name, value: value, forHost: host)
    }
    
    /**
     Sets global HTTP Basic auth credentials for all requests. Use an RequestModificationClosure (see downloadImageFromUrl) to set credentials for individual requests.
     
     - parameter credentials: the credentials to be used. Pass nil to remove credentials.
     - parameter host:        if given, the credentials are only set for requests to the specific host
     */
    public func setGlobalBasicAuthCredentials(credentials: NSURLCredential?, forHost host: String? = nil) {
        globalCredentials.setCredentials(credentials, forHost: host)
    }
    
    /**
     Sets global HTTP Basic auth credentials for all requests. Use an RequestModificationClosure (see downloadImageFromUrl) to set credentials for individual requests.
     
     - parameter user:     the user name to be used. Pass nil to remove credentials.
     - parameter password: the password to be used. Pass nil to remove credentials.
     - parameter host:     if given, the credentials are only set for requests to the specific host
     */
    public func setGlobalBasicAuthCredentials(user user: String?, password: String?, forHost host: String? = nil) {
        if let user = user, password = password {
            globalCredentials.setCredentials(NSURLCredential(user: user, password: password, persistence: .None), forHost: host)
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
    public func storeImage(imageData: NSData?, forUrl url: NSURL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            storeImage(imageData, forKey: cacheKey)
        }
    }
    
    /**
     Stores an image in the cache

     - parameter imageData: the image data to store
     - parameter key:       the cache key to use
     */
    public func storeImage(imageData: NSData?, forKey key: String?) {
        if let cacheKey = key, imageData = imageData, image = UIImage(data: imageData), tmpUrl = tmpFileWithData(imageData) {
            cacheImage(image, key: cacheKey, tempImageFile: tmpUrl, memCacheOnly: false)
        }
    }
    
    /**
     Fetches an image from the cache with the given cache key
     
     - parameter key: the cache key to use
     
     - returns: an instance of UIImage or nil
     */
    public func retrieveCachedImageForKey(key: String?) -> UIImage? {
        if let cacheKey = key {
            return retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        }
        return nil
    }
    
    public func retrieveCachedImageForKey(key: String?, completion: (image: UIImage?) -> ()) {
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
    public func retrieveCachedImageForUrl(url: NSURL?) -> UIImage? {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            return retrieveCachedImageForKey(cacheKey)
        }
        return nil
    }
    
    public func retrieveCachedImageForUrl(url: NSURL?, completion: (image: UIImage?) -> ()) {
        if let url = url {
            let cacheKey = self.transformUrlToCacheKey(url.absoluteString)
            retrieveCachedImageForKey(cacheKey, completion: completion)
        } else {
            completion(image: nil)
        }
    }
    
    /**
     Deletes an image from the cache
     
     - parameter url: the URL for the image to be deleted
     */
    public func deleteCachedImageForUrl(url: NSURL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            deleteCachedImageForKey(cacheKey)
        }
    }
    
    /**
     Invalides a running download. An invalidated download is not canceled. Instead, the download continues in the background and the downloaded image is stored in the cache. However, no completion blocks are called.
     
     - parameter downloadIdentifier: the download identifier whose associated download should be invalidated
     */
    public func invalidate(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.invalidateRequest(downloadIdentifier)
        }
    }
    
    /**
     Cancels a running download
     
     - parameter downloadIdentifier: the download identifier whose associated download should be canceled
     */
    public func cancel(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.cancelRequest(downloadIdentifier)
        }
    }
    
    // MARK: - Caching
    private func cacheImage(image: UIImage, key: String, tempImageFile: NSURL, memCacheOnly: Bool) {
        var fileSize: Int
        
        if let path = tempImageFile.path {
            do {
                let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(path)
                fileSize = (attributes[NSFileSize] as? NSNumber ?? 0).integerValue
            } catch {
                fileSize = 0
            }
        } else {
            fileSize = 0
        }
        
        let cacheEntry = VincentCacheEntry(cacheKey: key, image: image, lastAccessed: NSDate(), fileSize: fileSize)
        
        // mem cache
        memoryCache.setObject(cacheEntry, forKey: key, cost: fileSize)
        
        // disk cache
        if useDiskCache && !memCacheOnly {
            saveCacheEntryToDisk(cacheEntry, tempImageFile: tempImageFile, forKey: key)
        }
    }
    
    private func retrieveCachedImageForKey(key: String?, ignoreLastAccessed: Bool, completion: (image: UIImage?) -> ()) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            let image = self.retrieveCachedImageForKey(key, ignoreLastAccessed: ignoreLastAccessed)
            
            dispatch_async(dispatch_get_main_queue(), { 
                completion(image: image)
            })
        }
    }
    
    private func retrieveCachedImageForKey(key: String?, ignoreLastAccessed: Bool) -> UIImage? {
        if let key = key {
            var cacheEntry = memoryCache.objectForKey(key) as? VincentCacheEntry
            
            if cacheEntry == nil && useDiskCache {
                cacheEntry = loadCacheEntryFromDiskForKey(key)
                
                if let cacheEntry = cacheEntry {
                    memoryCache.setObject(cacheEntry, forKey: key, cost: cacheEntry.fileSize)
                }
            }
            
            if let cacheEntry = cacheEntry where cacheEntry.lastAccessed.timeIntervalSinceDate(NSDate()) < -cacheInvalidationTimeout {
                // stale
                deleteCachedImageForKey(key)
                return nil
            } else {
                cacheEntry?.lastAccessed = NSDate()
                if useDiskCache {
                    saveCacheEntryToDisk(cacheEntry, tempImageFile: nil, forKey: key)
                }
                return cacheEntry?.image
            }
        } else {
            return nil
        }
    }
    
    private func deleteCachedImageForKey(key: String?) {
        if let key = key {
            memoryCache.removeObjectForKey(key)
            if useDiskCache {
                saveCacheEntryToDisk(nil, tempImageFile: nil, forKey: key)
            }
        }
    }
    
    private func loadCacheEntryFromDiskForKey(key: String?) -> VincentCacheEntry? {
        if let key = key {
            let url = diskCacheFolderUrl.URLByAppendingPathComponent(key, isDirectory: false)
            if let path = url.path {
                dispatch_semaphore_wait(self.diskCacheSemaphore, DISPATCH_TIME_FOREVER)
                
                defer {
                    dispatch_semaphore_signal(self.diskCacheSemaphore)
                }
                
                if NSFileManager.defaultManager().fileExistsAtPath(path) {
                    var lastAccess : AnyObject?
                    do {
                        try url.getResourceValue(&lastAccess, forKey: NSURLContentAccessDateKey)
                    } catch {
                        return nil
                    }
                    
                    if let lastAccess = lastAccess as? NSDate {
                        let image = UIImage(contentsOfFile: path)
                        if let image = image {
                            var fileSize = 0
                            do {
                                let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(path)
                                fileSize = (attributes[NSFileSize] as? NSNumber ?? 0).integerValue
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
    
    private func saveCacheEntryToDisk(cacheEntry: VincentCacheEntry?, tempImageFile: NSURL?, forKey key: String?) {
        guard let key = key else {return}
        
        let url = diskCacheFolderUrl.URLByAppendingPathComponent(key, isDirectory: false)
        
        dispatch_semaphore_wait(self.diskCacheSemaphore, DISPATCH_TIME_FOREVER);
        if let tempImageFile = tempImageFile { // store new image
            
        _ = try? NSFileManager.defaultManager().moveItemAtURL(tempImageFile, toURL: url)
        } else if let cacheEntry = cacheEntry { // update image access date
            _ = try? url.setResourceValue(cacheEntry.lastAccessed, forKey: NSURLContentAccessDateKey)
        } else { // delete image
            _ = try? NSFileManager.defaultManager().removeItemAtURL(url)
        }
        dispatch_semaphore_signal(self.diskCacheSemaphore)
    }
    
    // MARK: - Utility
    private func validateResponse(response: NSURLResponse?) throws {
        guard let response = response as? NSHTTPURLResponse else {
            throw NSError(domain: "Vincent", code: 1, userInfo: [NSLocalizedDescriptionKey: "unexpected response"])
        }
        
        if response.statusCode >= 400 {
            throw NSError(domain: "Vincent", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode)])
        }
        
        if let mimeType = response.MIMEType {
            if !mimeType.hasPrefix("image/") {
                throw NSError(domain: "Vincent", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid mime type"])
            }
        }
    }
    
    private func transformUrlToCacheKey(url: String) -> String {
        if let key = keyCache.objectForKey(url) as? String {
            return key
        } else {
            let key = url.md5()
            keyCache.setObject(key, forKey: url)
            return key
        }
    }
    
    private func tmpFileWithData(data: NSData) -> NSURL? {
        let uuid = NSUUID().UUIDString
        let tmpFileUrl = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(uuid)
        if data.writeToURL(tmpFileUrl, atomically: true) {
            return tmpFileUrl
        } else {
            return nil
        }
    }
    
    private func cleanup() {
        self.memoryCache.removeAllObjects()
        guard let path = diskCacheFolderUrl.path else {return}
        
        do {
            let filesArray = try NSFileManager.defaultManager().contentsOfDirectoryAtPath(path)
            let now = NSDate()
            for file in filesArray {
                let url : NSURL = diskCacheFolderUrl.URLByAppendingPathComponent(file, isDirectory: false)
                var lastAccess : AnyObject?
                do {
                    try url.getResourceValue(&lastAccess, forKey: NSURLContentAccessDateKey)
                    if let lastAccess = lastAccess as? NSDate {
                        if (now.timeIntervalSinceDate(lastAccess) > 30 * 24 * 3600) {
                            try NSFileManager.defaultManager().removeItemAtURL(url)
                        }
                    }
                } catch {
                    continue
                }
                
            }
        } catch {}
    }
    
    // MARK: - Notifications
    internal func appWillResignActive(notification: NSNotification) {
        cleanup()
    }
    
    // MARK: - Memory
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
        cleanup()
    }
}

// MARK: - VincentCacheEntry
private class VincentCacheEntry: NSObject {
    var image : UIImage
    var lastAccessed : NSDate
    var cacheKey : String
    var fileSize : Int
    
    init(cacheKey: String, image: UIImage, lastAccessed: NSDate, fileSize: Int) {
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
    
    func setHeader(name: String, value: String?, forHost host: String?) {
        if let host = host {
            var headers = specificHostHeaders[host] ?? [String: String]()
            headers[name] = value
            specificHostHeaders[host] = headers
        } else {
            allHostsHeaders[name] = value
        }
    }
    
    func setHeaders(headers: [String: String], forHost host: String?) {
        if let host = host {
            specificHostHeaders[host] = headers
        } else {
            allHostsHeaders = headers
        }
    }
    
    func headersForHost(host: String?) -> [String: String] {
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
    private var allHostsCredentials: NSURLCredential?
    private var specificHostCredentials = [String: NSURLCredential]()
    
    func setCredentials(credentials: NSURLCredential?, forHost host: String?) {
        if let host = host {
            specificHostCredentials[host] = credentials
        } else {
            allHostsCredentials = credentials
        }
    }
    
    func credentialsForHost(host: String?) -> NSURLCredential? {
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
