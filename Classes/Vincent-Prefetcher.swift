//
//  Vincent-Prefetcher.swift
//
//  Created by Kai Straßmann

import Foundation

public class Prefetcher {
    private weak var vincent: Vincent?
    private let queue: NSOperationQueue
    public var maxConcurrentOperationCount: Int = 4 {
        didSet {
            queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        }
    }
    public var operationTimeout: Int = 20
    public var cacheType: CacheType = .Automatic
    
    init(vincent: Vincent) {
        self.vincent = vincent
        queue = NSOperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
    
    public func fetchWithString(stringUrl: String?) {
        if let stringUrl = stringUrl, url = NSURL(string: stringUrl) {
            fetchWithUrl(url, completion: nil)
        }
    }
    
    public func fetchWithUrl(url: NSURL?) {
        if let url = url {
            fetchWithUrl(url, completion: nil)
        }
    }
    
    public func fetchWithString(stringUrl: String?, completion: CompletionClosure?) {
        if let stringUrl = stringUrl, url = NSURL(string: stringUrl) {
            fetchWithUrl(url, completion: completion)
        }
    }
    
    public func fetchWithUrl(url: NSURL, completion: CompletionClosure?) {
        var operation: PrefetchOperation
        
        if let existingOperation = operationWithUrl(url) {
            operation = existingOperation
            if !operation.addCompletion(completion) {
                operation = PrefetchOperation(url: url, prefetcher: self)
                operation.addCompletion(completion)
                queue.addOperation(operation)
            }
        } else {
            operation = PrefetchOperation(url: url, prefetcher: self)
            operation.addCompletion(completion)
            queue.addOperation(operation)
        }
    }
    
    public func cancelAll() {
        queue.cancelAllOperations()
    }
    
    private func operationWithUrl(url: NSURL) -> PrefetchOperation? {
        return queue.operations.filter({ o in
            if let o = o as? PrefetchOperation {
                return !o.cancelled && !o.finished && !o.closuresCalled && o.url == url
            } else {
                return false
            }
        }).first as? PrefetchOperation
    }
}

class PrefetchOperation: NSOperation {
    private(set) var url: NSURL
    private weak var prefetcher: Prefetcher?
    private var completionClosures = Array<CompletionClosure>()
    private var downloadSemaphore = dispatch_semaphore_create(0)
    private var completionClosuresSemaphore = dispatch_semaphore_create(1)
    var closuresCalled = false
    
    
    init(url: NSURL, prefetcher: Prefetcher) {
        self.url = url
        self.prefetcher = prefetcher
        super.init()
    }
    
    func addCompletion(completion: CompletionClosure?) -> Bool {
        if let completion = completion {
            dispatch_semaphore_wait(completionClosuresSemaphore, DISPATCH_TIME_FOREVER)
            defer {
                dispatch_semaphore_signal(completionClosuresSemaphore)
            }
            
            if closuresCalled {
                return false
            }
            completionClosures.append(completion)
            return true
        } else {
            return true
        }
    }
    
    override func main() {
        super.main()
        guard let prefetcher = prefetcher, vincent = prefetcher.vincent else {return}
        
        vincent.downloadImageFromUrl(url, cacheType: prefetcher.cacheType, success: { image in
            dispatch_semaphore_wait(self.completionClosuresSemaphore, DISPATCH_TIME_FOREVER)
            for completionClosure in self.completionClosures {
                dispatch_sync(dispatch_get_main_queue()) {
                    completionClosure(error: nil, image: image)
                }
            }
            self.closuresCalled = true
            dispatch_semaphore_signal(self.completionClosuresSemaphore)
            
            dispatch_semaphore_signal(self.downloadSemaphore)
        }, error: { error in
            dispatch_semaphore_wait(self.completionClosuresSemaphore, DISPATCH_TIME_FOREVER)
            for completionClosure in self.completionClosures {
                dispatch_sync(dispatch_get_main_queue()) {
                    completionClosure(error: error, image: nil)
                }
            }
            self.closuresCalled = true
            dispatch_semaphore_signal(self.completionClosuresSemaphore)
            
            dispatch_semaphore_signal(self.downloadSemaphore)
        })
        
        let timeout = dispatch_time(DISPATCH_TIME_NOW, Int64(Double(prefetcher.operationTimeout) * Double(NSEC_PER_SEC)))
        dispatch_semaphore_wait(downloadSemaphore, timeout)
        
        dispatch_semaphore_wait(self.completionClosuresSemaphore, DISPATCH_TIME_FOREVER)
        if !self.closuresCalled {
            let error = NSError(domain: "Vincent", code: -4, userInfo: [NSLocalizedDescriptionKey: "prefetcher timeout"])
            
            for completionClosure in completionClosures {
                dispatch_sync(dispatch_get_main_queue()) {
                    completionClosure(error: error, image: nil)
                }
            }
            completionClosures.removeAll()
            self.closuresCalled = true
        }
        dispatch_semaphore_signal(self.completionClosuresSemaphore)
    }
}