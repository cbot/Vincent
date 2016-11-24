import UIKit

public protocol VincentURL {
    var toUrl: URL? { get }
}
extension URL: VincentURL {
    public var toUrl: URL? { return self }
}
extension String: VincentURL {
    public var toUrl: URL? { return URL(string: self) }
}

fileprivate var handlerKey = "handler"
public class VincentViewHandler: NSObject {
    private var downloadIdentifiers = Set<String>()
    
    func cancel() {
        for identifier in downloadIdentifiers {
            Vincent.sharedInstance.cancelDownload(identifier: identifier)
        }
        downloadIdentifiers.removeAll()
    }
    
    func invalidate() {
        for identifier in downloadIdentifiers {
            Vincent.sharedInstance.invalidateDownload(identifier: identifier)
        }
        downloadIdentifiers.removeAll()
    }
    
    func load(url: URL?, cacheType: CacheType, requestModification: ((_ request: URLRequest) -> URLRequest)?, completion: ((_ result: VincentImageCompletionType) -> ())?) {
        
        if let url = url {
            let identifier = UUID().uuidString
            downloadIdentifiers.insert(identifier)
            Vincent.sharedInstance.retrieveImage(fromUrl: url, cacheType: cacheType, requestModification: nil, customIdentifier: identifier, completion: { [weak self] result in
                if self?.downloadIdentifiers.contains(identifier) ?? false {
                    self?.downloadIdentifiers.remove(identifier)
                    completion?(result)
                } else {
                    completion?(.canceledOrInvalidated)
                }
            })
        }
    }
}

extension UIImageView {
    public var vincent: VincentViewHandler {
        if let obj = objc_getAssociatedObject(self, &handlerKey) as? VincentViewHandler {
            return obj
        } else {
            let obj = VincentViewHandler()
            objc_setAssociatedObject(self, &handlerKey, obj, .OBJC_ASSOCIATION_RETAIN)
            return obj
        }
    }
    
    public func cancelImageDownload() {
        vincent.cancel()
    }
    
    public func invalidateImageDownload() {
        vincent.invalidate()
    }
    
    public func setImage(withUrl vincentUrl: VincentURL, placeholder: UIImage? = nil, cacheType: CacheType = .automatic, requestModification: ((_ request: URLRequest) -> URLRequest)? = nil, completion: ((_ result: VincentImageCompletionType) -> ())? = nil) {
        
        var loaded = false
        
        if let placeholder = placeholder {
            image = placeholder
        } else {
            // try to fetch from cache
            image = nil
            vincent.load(url: vincentUrl.toUrl, cacheType: .fromCache, requestModification: requestModification, completion: { [weak self] result in
                if case .image(let image) = result {
                    if !loaded {
                        self?.image = image
                    }
                }
            })
        }
        
        vincent.load(url: vincentUrl.toUrl, cacheType: cacheType, requestModification: requestModification) { [weak self] result in
            if case .image(let image) = result {
                loaded = true
                self?.image = image
            }
            completion?(result)
        }
    }
}


extension UIButton {
    public var vincent: VincentViewHandler {
        if let obj = objc_getAssociatedObject(self, &handlerKey) as? VincentViewHandler {
            return obj
        } else {
            let obj = VincentViewHandler()
            objc_setAssociatedObject(self, &handlerKey, obj, .OBJC_ASSOCIATION_RETAIN)
            return obj
        }
    }
    
    public func cancelImageDownload() {
        vincent.cancel()
    }
    
    public func invalidateImageDownload() {
        vincent.invalidate()
    }
    
    public func setImage(withUrl vincentUrl: VincentURL, for controlState: UIControlState, placeholder: UIImage? = nil, cacheType: CacheType = .automatic, requestModification: ((_ request: URLRequest) -> URLRequest)? = nil, completion: ((_ result: VincentImageCompletionType) -> ())? = nil) {
        
        var loaded = false
        
        if let placeholder = placeholder {
            setImage(placeholder, for: controlState)
        } else {
            setImage(nil, for: controlState)
            // try to fetch from cache
            vincent.load(url: vincentUrl.toUrl, cacheType: .fromCache, requestModification: requestModification, completion: { [weak self] result in
                if case .image(let image) = result {
                    if !loaded {
                        self?.setImage(image, for: controlState)
                    }
                }
            })
        }
        
        vincent.load(url: vincentUrl.toUrl, cacheType: cacheType, requestModification: requestModification) { [weak self] result in
            if case .image(let image) = result {
                loaded = true
                self?.setImage(image, for: controlState)
            }
            completion?(result)
        }
    }
}
