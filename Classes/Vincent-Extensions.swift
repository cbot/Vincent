//
//  Vincent-Utils.swift
//
//  Created by Kai Straßmann

import UIKit
import ObjectiveC

private var downloadTaskKey: UInt8 = 0
private var numRequestsKey: UInt8 = 0

public extension UIImageView {
    var downloadTaskIdentifier: String? {
        get {
            return objc_getAssociatedObject(self, &downloadTaskKey) as? String
        }
        set(newValue) {
            objc_setAssociatedObject(self, &downloadTaskKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var numRequests: Int {
        get {
            return objc_getAssociatedObject(self, &numRequestsKey) as? Int ?? 0
        }
        set(newValue) {
            objc_setAssociatedObject(self, &numRequestsKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
            if let vincentImageView = self as? VincentImageView {
                if newValue > 0 && vincentImageView.showsSpinner && (vincentImageView.showsSpinnerOnPlaceholder || vincentImageView.image == nil) {
                    vincentImageView.activityIndicator.startAnimating()
                } else {
                    vincentImageView.activityIndicator.stopAnimating()
                }
            }
        }
    }
    
    func setImageWithString(urlString: String?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, completion: CompletionClosure?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, placeHolder: UIImage?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), placeHolder: placeHolder, cacheType: cacheType, requestModification: requestModification, completion: completion)
        }
    }
    
    func setImageWithUrl(url: NSURL?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, completion: CompletionClosure?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        let downloader = Vincent.sharedInstance
        downloader.invalidate(self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            self.image = placeHolder
        } else {
            self.image = downloader.retrieveCachedImageForUrl(url)
        }
        
        guard let url = url else {return}
        
        numRequests += 1
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, requestModification: requestModification, requestDone: { [weak self] in
            dispatch_async(dispatch_get_main_queue()) {
                if let vincentImageView = self as? VincentImageView where vincentImageView.showsSpinner {
                    self?.numRequests -= 1
                }
            }
        }) { [weak self] image, error in
            self?.downloadTaskIdentifier = nil
            guard let image = image else {
                dispatch_async(dispatch_get_main_queue(), {
                    completion?(image: nil, error: error)
                })
                return
            }
            
            dispatch_async(dispatch_get_main_queue(), {
                self?.image = image
                completion?(image: image, error: nil)
            })
        }
    }
    
    func cancelImageDownload() {
        Vincent.sharedInstance.cancel(self.downloadTaskIdentifier)
        self.downloadTaskIdentifier = nil
    }
    
    func invalidateImageDownload() {
        Vincent.sharedInstance.invalidate(self.downloadTaskIdentifier)
        self.downloadTaskIdentifier = nil
    }
}

public extension UIButton {
    var downloadTaskIdentifier: String? {
        get {
            return objc_getAssociatedObject(self, &downloadTaskKey) as? String
        }
        set(newValue) {
            objc_setAssociatedObject(self, &downloadTaskKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, completion: CompletionClosure?) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), forState: state, placeHolder: placeHolder, cacheType: cacheType, requestModification: requestModification, completion: completion)
        }
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, completion: CompletionClosure?) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithUrl(url, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithUrl(url, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        let downloader = Vincent.sharedInstance
        downloader.invalidate(self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            setImage(placeHolder, forState: state)
        } else {
            setImage(downloader.retrieveCachedImageForUrl(url), forState: state)
        }
        
        guard let url = url else {return}
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, requestModification: requestModification) { [weak self] image, error in
            self?.downloadTaskIdentifier = nil
            guard let image = image else {
                dispatch_async(dispatch_get_main_queue(), {
                    completion?(image: nil, error: error)
                })
                return
            }
        
            dispatch_async(dispatch_get_main_queue(), {
                self?.setImage(image, forState: state)
                completion?(image: image, error: nil)
            })
        }
    }
    
    func cancelImageDownload() {
        Vincent.sharedInstance.cancel(self.downloadTaskIdentifier)
        self.downloadTaskIdentifier = nil
    }
    
    func invalidateImageDownload() {
        Vincent.sharedInstance.invalidate(self.downloadTaskIdentifier)
        self.downloadTaskIdentifier = nil
    }
}
