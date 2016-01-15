//
//  Vincent.swift
//
//  Created by Kai Straßmann

import UIKit
import MD5Digest

public typealias CompletionClosure = (image: UIImage?, error: NSError?) -> Void
public typealias RequestModificationClosure = (request: Request) -> Void

@objc public enum CacheType: Int {
    case Automatic     // if a non stale image is contained in the cache, it is used. otherwise Protocol cache type is used
    case ForceCache    // if the image is contained in the cache (no matter how old), it is used. otherwise Protocol cache type is used
    case ForceDownload // ALWAYS creates a download task, ignores any cache headers from the server
    case Protocol      // ALWAYS creates a download task, cache headers decide if a request is actually made
}

@objc public class Vincent : NSObject {
    public static let sharedInstance = Vincent(identifier: "shared-downloader")
    
    public lazy var prefetcher: Prefetcher = Prefetcher(vincent: self)

    public var trustAllCertificates = false
    public var useDiskCache = true
    public var timeoutInterval = 30.0
    public var cacheInvalidationTimeout : NSTimeInterval = 1 * 24 * 3600
    public var memoryCacheSize : Int = 64 * 1024 * 1024 {
        willSet {
            memoryCache.totalCostLimit = newValue
        }
    }

    private var downloader = VincentDowloader()
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
    private var globalRequestHeaders = [String: String]()
    private var globalCredentials: NSURLCredential?
    
    // MARK: - Constructor
    public init(identifier: String) {
        let cachesDirectory = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first!
        diskCacheFolderUrl = NSURL(fileURLWithPath: cachesDirectory).URLByAppendingPathComponent(identifier, isDirectory: false)
        do {
            try NSFileManager.defaultManager().createDirectoryAtURL(diskCacheFolderUrl, withIntermediateDirectories: true, attributes: nil)
        } catch let error {
            print("Vincent: unable to create disk cache folder: \(error)")
        }
        super.init()
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "appWillResignActive:", name: UIApplicationWillResignActiveNotification, object: nil)
    }
    
    // MARK: - Public methods    
    public func downloadImageFromUrl(url: NSURL, cacheType: CacheType, callErrorOnCancel: Bool = false, requestDone requestDoneBlock: (() -> ())? = nil, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) -> String? {
        var image : UIImage?
        let cacheKey = transformUrlToCacheKey(url.absoluteString)
        
        if cacheType == .ForceCache {
            image = retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        } else if cacheType == .Automatic {
            image = retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: false)
        } else {
            image = nil
        }
                
        if image != nil {
            requestDoneBlock?()
            completion?(image: image, error: nil)
            return nil
        }
        
        if url.fileURL {
            if let data = NSData(contentsOfURL: url), image = UIImage(data: data) {
                cacheImage(image, key: cacheKey, tempImageFile: url, memCacheOnly: true)
                requestDoneBlock?()
                completion?(image: image, error: nil)
            } else {
                requestDoneBlock?()
                completion?(image: nil, error: NSError(domain: "Vincent", code: -6, userInfo: [NSLocalizedDescriptionKey: "unable to load image from file url"]))
            }
            return nil
        } else {
            let request = downloader.request(url, cachePolicy: cacheType == .ForceDownload ? .ReloadIgnoringLocalCacheData : .UseProtocolCachePolicy, timeoutInterval: timeoutInterval)
            
            request.header("Accept", withValue: "image/*")
            for (key, value) in globalRequestHeaders {
                request.header(key, withValue: value)
            }
            
            if let credentials = globalCredentials, user = credentials.user, password = credentials.password {
                request.credentials(user: user, password: password)
            }
            
            if trustAllCertificates {
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
                        
                        image = UIImage(data: data)
                        if let image = image {
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
            
            downloader.executeRequest(request)
            return request.identifier
        }
    }
    
    public func setGlobalHeaderValue(value: String?, forHeaderWithName name: String) {
        globalRequestHeaders[name] = value
    }
    
    public func setGlobalBasicAuthCredentials(credentials: NSURLCredential?) {
        globalCredentials = credentials
    }
    
    public func setGlobalBasicAuthCredentials(user user: String?, password: String?) {
        if let user = user, password = password {
            globalCredentials = NSURLCredential(user: user, password: password, persistence: .None)
        } else {
            globalCredentials = nil
        }
    }
    
    public func storeImage(imageData: NSData?, forUrl url: NSURL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            storeImage(imageData, forKey: cacheKey)
        }
    }
    
    public func storeImage(imageData: NSData?, forKey key: String?) {
        if let cacheKey = key, imageData = imageData, image = UIImage(data: imageData), tmpUrl = tmpFileWithData(imageData) {
            cacheImage(image, key: cacheKey, tempImageFile: tmpUrl, memCacheOnly: false)
        }
    }
    
    public func retrieveCachedImageForKey(key: String?) -> UIImage? {
        if let cacheKey = key {
            return retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        }
        return nil
    }
    
    public func retrieveCachedImageForUrl(url: NSURL?) -> UIImage? {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            return retrieveCachedImageForKey(cacheKey)
        }
        return nil
    }
    
    public func deleteCachedImageForUrl(url: NSURL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString)
            deleteCachedImageForKey(cacheKey)
        }
    }
    
    public func invalidate(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.invalidateRequest(downloadIdentifier)
        }
    }
    
    public func cancel(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            downloader.cancelRequest(downloadIdentifier)
        }
    }
    
    // MARK: - Caching
    private func cacheImage(image: UIImage, key: String, tempImageFile: NSURL, memCacheOnly: Bool) {
        var fileSize: Int
        do {
            let attributes = try NSFileManager.defaultManager().attributesOfItemAtPath(tempImageFile.path!)
            fileSize = (attributes[NSFileSize] as! NSNumber!).integerValue
        } catch {
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
    
    private func retrieveCachedImageForKey(key: String?, ignoreLastAccessed: Bool) -> UIImage? {
        if let key = key {
            var cacheEntry = memoryCache.objectForKey(key) as! VincentCacheEntry?
            if cacheEntry == nil && useDiskCache {
                cacheEntry = loadCacheEntryFromDiskForKey(key)
                if cacheEntry != nil {
                    memoryCache.setObject(cacheEntry!, forKey: key, cost: cacheEntry!.fileSize)
                }
            }
            
            if cacheEntry != nil && cacheEntry!.lastAccessed.timeIntervalSinceDate(NSDate()) < -cacheInvalidationTimeout {
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
                dispatch_semaphore_wait(self.diskCacheSemaphore, DISPATCH_TIME_FOREVER);
                
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
                                fileSize = (attributes[NSFileSize] as! NSNumber!).integerValue
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
        if let key = keyCache.objectForKey(url) as! String? {
            return key
        } else {
            let key = md5(url)
            keyCache.setObject(key, forKey: url)
            return key
        }
    }
    
    private func md5(input: String) -> String! {
        return (input as NSString).MD5Digest()
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
class VincentCacheEntry: NSObject {
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