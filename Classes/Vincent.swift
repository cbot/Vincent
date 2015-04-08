//
//  Vincent.swift
//
//  Created by Kai Straßmann

import UIKit
import CryptoSwift

public enum CacheType {
    case Automatic     // if a non stale image is contained in the cache, it is used. otherwise Protocol cache type is used
    case ForceCache    // if the image is contained in the cache (no matter how old), it is used. otherwise Protocol cache type is used
    case ForceDownload // ALWAYS creates a download task, ignores any cache headers from the server
    case Protocol      // ALWAYS creates a download task, cache headers decide if a request is actually made
}

@objc public class Vincent : NSObject {
    public class var sharedInstance: Vincent {
        struct Singleton {
            static let instance = Vincent(identifier: "shared-downloader")
        }
        return Singleton.instance
    }

    var useDiskCache = true
    var timeoutInterval = 30.0
    var cacheInvalidationTimeout : NSTimeInterval = 1 * 24 * 3600
    var memoryCacheSize : Int = 64 * 1024 * 1024 {
        willSet {
            memoryCache.totalCostLimit = newValue
        }
    }

    private(set) var diskCacheFolderUrl : NSURL
    private lazy var urlSession : NSURLSession = {
        let configuration =  NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.HTTPMaximumConnectionsPerHost = 10
        configuration.HTTPShouldUsePipelining = true
       return NSURLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
    }()
    
    private lazy var memoryCache : NSCache = {
        var cache = NSCache()
        cache.totalCostLimit = self.memoryCacheSize
        return cache
    }()
    
    private lazy var keyCache : NSCache = {
        var cache = NSCache()
        cache.countLimit = 512
        return cache
    }()
    
    private var diskCacheSemaphore = dispatch_semaphore_create(1);
    private var runningDownloadsSemaphore = dispatch_semaphore_create(1);
    private var runningDownloads : Dictionary<String, NSURLSessionDownloadTask> = Dictionary<String, NSURLSessionDownloadTask>()
    
    // MARK: - Constructor
    public init(identifier: String) {
        var cachesDirectory = NSSearchPathForDirectoriesInDomains(.CachesDirectory, .UserDomainMask, true).first as String
        diskCacheFolderUrl = NSURL(fileURLWithPath: cachesDirectory)!.URLByAppendingPathComponent(identifier, isDirectory: false)
        NSFileManager.defaultManager().createDirectoryAtURL(diskCacheFolderUrl, withIntermediateDirectories: true, attributes: nil, error: nil);
        super.init()
        NSNotificationCenter .defaultCenter().addObserver(self, selector: "appWillResignActive:", name: UIApplicationWillResignActiveNotification, object: nil)
    }
    
    // MARK: - Public methods
    public func downloadImageFromUrl(url: NSURL, cacheType: CacheType, success successBlock: ((image: UIImage) -> ())?, error errorBlock: ((error: NSError) -> ())?) -> String? {
        var image : UIImage?
        let cacheKey = transformUrlToCacheKey(url.absoluteString!)
        
        if cacheType == .ForceCache {
            image = retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        } else if cacheType == .Automatic {
            image = retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: false)
        } else {
            image = nil
        }
                
        if image != nil {
            successBlock?(image: image!)
            return nil;
        }
        
        let uuid = NSUUID().UUIDString
        
        let request : NSURLRequest = NSURLRequest(URL: url, cachePolicy: cacheType == .ForceDownload ? .ReloadIgnoringLocalCacheData : .UseProtocolCachePolicy, timeoutInterval: timeoutInterval)
        let downloadTask = urlSession.downloadTaskWithRequest(request) {[weak self] (tmpImageUrl, response, error) -> Void in
            if let this = self {
                let taskInvalidated = self?.runningDownloads[uuid] == nil
                
                if error != nil {
                    if (!taskInvalidated) {
                        errorBlock?(error: error!)
                    }
                } else {
                    var error : NSError?
                    if this.validateResponse(response as NSHTTPURLResponse, error: &error) {
                        image = UIImage(data: NSData(contentsOfFile: tmpImageUrl.path!)!)
                        if let image = image {
                            this.cacheImage(image, key: cacheKey, tempImageFile: tmpImageUrl)
                            if (!taskInvalidated) {
                                successBlock?(image: image)
                            }
                        } else if (!taskInvalidated) {
                            errorBlock?(error: NSError(domain: "Vincent", code: -2, userInfo:[NSLocalizedDescriptionKey: "unable to decode image"]))
                        }
                    } else if (!taskInvalidated) {
                        errorBlock?(error: error!)
                    }
                }
            }
        }
        
        dispatch_semaphore_wait(self.runningDownloadsSemaphore, DISPATCH_TIME_FOREVER)
        runningDownloads[uuid] = downloadTask
        dispatch_semaphore_signal(self.runningDownloadsSemaphore)
        downloadTask.resume()
        return uuid
    }
    
    public func retrieveCachedImageForUrl(url: NSURL?) -> UIImage? {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString!)
            return retrieveCachedImageForKey(cacheKey, ignoreLastAccessed: true)
        }
        return nil
    }
    
    public func deleteCachedImageForUrl(url: NSURL?) {
        if let url = url {
            let cacheKey = transformUrlToCacheKey(url.absoluteString!)
            deleteCachedImageForKey(cacheKey)
        }
    }
    
    public func invalidate(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            dispatch_semaphore_wait(self.runningDownloadsSemaphore, DISPATCH_TIME_FOREVER)
            runningDownloads.removeValueForKey(downloadIdentifier)
            dispatch_semaphore_signal(self.runningDownloadsSemaphore)
        }
    }
    
    public func cancel(downloadIdentifier: String?) {
        if let downloadIdentifier = downloadIdentifier {
            dispatch_semaphore_wait(self.runningDownloadsSemaphore, DISPATCH_TIME_FOREVER)
            let task = runningDownloads[downloadIdentifier]
            dispatch_semaphore_signal(self.runningDownloadsSemaphore)
            task?.cancel()
            invalidate(downloadIdentifier)
        }
    }
    
    // MARK: - Caching
    private func cacheImage(image: UIImage, key: String, tempImageFile: NSURL) {
        var fileSize = 0
        if let attributes = NSFileManager.defaultManager().attributesOfItemAtPath(tempImageFile.path!, error: nil) {
            fileSize = (attributes[NSFileSize] as NSNumber!).integerValue
        }
        
        let cacheEntry = VincentCacheEntry(cacheKey: key, image: image, lastAccessed: NSDate(), fileSize: fileSize)
        
        memoryCache.setObject(cacheEntry, forKey: key, cost: fileSize)
        if useDiskCache {
            saveCacheEntryToDisk(cacheEntry, tempImageFile: tempImageFile, forKey: key)
        }
    }
    
    private func retrieveCachedImageForKey(key: String?, ignoreLastAccessed: Bool) -> UIImage? {
        if let key = key {
            var cacheEntry = memoryCache.objectForKey(key) as VincentCacheEntry?
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
                if NSFileManager.defaultManager().fileExistsAtPath(path) {
                    var lastAccess : AnyObject?
                    url.getResourceValue(&lastAccess, forKey: NSURLContentAccessDateKey, error: nil)
                    
                    if let lastAccess = lastAccess as? NSDate {
                        var image = UIImage(contentsOfFile: path)
                        if let image = image {
                            var fileSize = 0
                            if let attributes = NSFileManager.defaultManager().attributesOfItemAtPath(path, error: nil) {
                                fileSize = (attributes[NSFileSize] as NSNumber!).integerValue
                            }
                            
                            let cacheEntry = VincentCacheEntry(cacheKey: key, image: image, lastAccessed: lastAccess, fileSize: fileSize)
                            dispatch_semaphore_signal(self.diskCacheSemaphore)
                            return cacheEntry
                        }
                    }
                }
                dispatch_semaphore_signal(self.diskCacheSemaphore)
            }
        }
        return nil
    }
    
    private func saveCacheEntryToDisk(cacheEntry: VincentCacheEntry?, tempImageFile: NSURL?, forKey key: String?) {
        if let key = key {
            let url = diskCacheFolderUrl.URLByAppendingPathComponent(key, isDirectory: false)
            
            dispatch_semaphore_wait(self.diskCacheSemaphore, DISPATCH_TIME_FOREVER);
            if let tempImageFile = tempImageFile { // store new image
                NSFileManager.defaultManager().moveItemAtURL(tempImageFile, toURL: url, error: nil)
            } else if let cacheEntry = cacheEntry { // update image access date
                url.setResourceValue(cacheEntry.lastAccessed, forKey: NSURLContentAccessDateKey, error: nil)
            } else { // delete image
                NSFileManager.defaultManager().removeItemAtURL(url, error: nil)
            }
            dispatch_semaphore_signal(self.diskCacheSemaphore)
        }
    }
    
    // MARK: - Utility
    private func validateResponse(response: NSHTTPURLResponse, error: NSErrorPointer) -> Bool {
        if response.statusCode >= 400 {
            error.memory = NSError(domain: "Vincent", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode)])
            return false
        }
        
        if let mimeType = response.MIMEType {
            if !mimeType.hasPrefix("image/") {
                error.memory = NSError(domain: "Vincent", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid mime type"])
                return false
            }
        }
        
        return true
    }
    
    private func transformUrlToCacheKey(url: String) -> String {
        if let key = keyCache.objectForKey(url) as String? {
            return key
        } else {
            let key = md5(url)
            keyCache.setObject(key, forKey: url)
            return key
        }
    }
    
    private func md5(input: String) -> String! {
        return input.md5()
    }
    
    private func cleanup() {
        self.memoryCache.removeAllObjects()
        if let path = diskCacheFolderUrl.path {
            if let filesArray = NSFileManager.defaultManager().contentsOfDirectoryAtPath(path, error: nil) {
                let now = NSDate()
                for file in filesArray as Array<String> {
                    let url : NSURL = diskCacheFolderUrl.URLByAppendingPathComponent(file, isDirectory: false)
                    var lastAccess : AnyObject?
                    url.getResourceValue(&lastAccess, forKey: NSURLContentAccessDateKey, error: nil)
                    
                    if let lastAccess = lastAccess as? NSDate {
                        if (now.timeIntervalSinceDate(lastAccess) > 30 * 24 * 3600) {
                            NSFileManager.defaultManager().removeItemAtURL(url, error: nil)
                        }
                    }
                }
            }
        }
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

// MARK: -
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