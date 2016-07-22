//
//  Vincent-Prefetcher.swift
//
//  Created by Kai Straßmann

import Foundation

@objc public class Prefetcher: NSObject {
    private weak var vincent: Vincent?
    private let queue: OperationQueue
    public var maxConcurrentOperationCount: Int = 4 {
        didSet {
            queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        }
    }
    public var operationTimeout: Int = 20
    public var cacheType: CacheType = .automatic
    
    init(vincent: Vincent) {
        self.vincent = vincent
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = maxConcurrentOperationCount
        super.init()
    }
    
    public func fetchWithString(_ stringUrl: String?) {
        if let stringUrl = stringUrl, let url = URL(string: stringUrl) {
            fetchWithUrl(url, completion: nil)
        }
    }
    
    public func fetchWithUrl(_ url: URL?) {
        if let url = url {
            fetchWithUrl(url, completion: nil)
        }
    }
    
    public func fetchWithString(_ stringUrl: String?, completion: CompletionClosure?) {
        if let stringUrl = stringUrl, let url = URL(string: stringUrl) {
            fetchWithUrl(url, completion: completion)
        }
    }
    
    public func fetchWithUrl(_ url: URL, completion: CompletionClosure?) {
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
    
    private func operationWithUrl(_ url: URL) -> PrefetchOperation? {
        return queue.operations.filter({ o in
            if let o = o as? PrefetchOperation {
                return !o.isCancelled && !o.isFinished && !o.closuresCalled && o.url == url
            } else {
                return false
            }
        }).first as? PrefetchOperation
    }
}

class PrefetchOperation: Operation {
    private(set) var url: URL
    private weak var prefetcher: Prefetcher?
    private var completionClosures = Array<CompletionClosure>()
    private var downloadSemaphore = DispatchSemaphore(value: 0)
    private var completionClosuresSemaphore = DispatchSemaphore(value: 1)
    var closuresCalled = false
    
    init(url: URL, prefetcher: Prefetcher) {
        self.url = url
        self.prefetcher = prefetcher
        super.init()
    }
    
    @discardableResult
    func addCompletion(_ completion: CompletionClosure?) -> Bool {
        if let completion = completion {
            let _ = completionClosuresSemaphore.wait(timeout: DispatchTime.distantFuture)
            defer {
                completionClosuresSemaphore.signal()
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
        guard let prefetcher = prefetcher, let vincent = prefetcher.vincent else {return}
        
        vincent.downloadImageFromUrl(url, cacheType: prefetcher.cacheType) { image, error in
            guard let image = image else {
                let _ = self.completionClosuresSemaphore.wait(timeout: DispatchTime.distantFuture)
                for completionClosure in self.completionClosures {
                    DispatchQueue.main.sync {
                        completionClosure(image: nil, error: error)
                    }
                }
                self.closuresCalled = true
                self.completionClosuresSemaphore.signal()
                self.downloadSemaphore.signal()
                return
            }
            
            let _ = self.completionClosuresSemaphore.wait(timeout: DispatchTime.distantFuture)
            for completionClosure in self.completionClosures {
                DispatchQueue.main.sync {
                    completionClosure(image: image, error: nil)
                }
            }
            self.closuresCalled = true
            self.completionClosuresSemaphore.signal()
            self.downloadSemaphore.signal()
        }
        
        let timeout = DispatchTime.now() + Double(Int64(Double(prefetcher.operationTimeout) * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        let _ = downloadSemaphore.wait(timeout: timeout)
        
        let _ = self.completionClosuresSemaphore.wait(timeout: DispatchTime.distantFuture)
        if !self.closuresCalled {
            let error = NSError(domain: "Vincent", code: -4, userInfo: [NSLocalizedDescriptionKey: "prefetcher timeout"])
            
            for completionClosure in completionClosures {
                DispatchQueue.main.sync {
                    completionClosure(image: nil, error: error)
                }
            }
            completionClosures.removeAll()
            self.closuresCalled = true
        }
        self.completionClosuresSemaphore.signal()
    }
}
