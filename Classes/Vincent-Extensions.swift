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
    
    func setImageWithString(_ urlString: String?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithString(_ urlString: String?, completion: CompletionClosure?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithString(_ urlString: String?, placeHolder: UIImage?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithString(_ urlString: String?, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithString(_ urlString: String?, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(URL(string: urlString), placeHolder: placeHolder, cacheType: cacheType, requestModification: requestModification, completion: completion)
        }
    }
    
    func setImageWithUrl(_ url: URL?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithUrl(_ url: URL?, completion: CompletionClosure?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithUrl(_ url: URL?, placeHolder: UIImage?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithUrl(_ url: URL?, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithUrl(_ url: URL?, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {        
        Vincent.sharedInstance.invalidateDownload(identifier: self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            self.image = placeHolder
        } else {
            self.image = Vincent.sharedInstance.retrieveCachedImage(url: url)
        }
        
        guard let url = url else { return }
        
        self.numRequests += 1
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, requestDone: { [weak self] in
            DispatchQueue.main.async {
                self?.numRequests -= 1
            }
        }, requestModification: requestModification) { [weak self] image, error in
            guard let image = image else {
                DispatchQueue.main.async(execute: {
                    completion?(nil, error)
                })
                return
            }
            
            DispatchQueue.main.async(execute: {
                self?.image = image
                completion?(image, nil)
            })
        }
    }
    
    func cancelImageDownload() {
        Vincent.sharedInstance.cancelDownload(identifier: self.downloadTaskIdentifier)
    }
    
    func invalidateImageDownload() {
        Vincent.sharedInstance.invalidateDownload(identifier: self.downloadTaskIdentifier)
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
    
    func setImageWithString(_ urlString: String?, forState state: UIControlState) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithString(_ urlString: String?, forState state: UIControlState, completion: CompletionClosure?) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithString(_ urlString: String?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithString(_ urlString: String?, forState state: UIControlState, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithString(_ urlString: String?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(URL(string: urlString), forState: state, placeHolder: placeHolder, cacheType: cacheType, requestModification: requestModification, completion: completion)
        }
    }
    
    func setImageWithUrl(_ url: URL?, forState state: UIControlState) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithUrl(_ url: URL?, forState state: UIControlState, completion: CompletionClosure?) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithUrl(_ url: URL?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithUrl(url, forState: state, placeHolder: placeHolder, cacheType: .automatic, completion: nil)
    }
    
    func setImageWithUrl(_ url: URL?, forState state: UIControlState, placeHolder: UIImage?, completion: CompletionClosure?) {
        setImageWithUrl(url, forState: state, placeHolder: placeHolder, cacheType: .automatic, completion: completion)
    }
    
    func setImageWithUrl(_ url: URL?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, requestModification: RequestModificationClosure? = nil, completion: CompletionClosure?) {
        
        Vincent.sharedInstance.invalidateDownload(identifier: self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            setImage(placeHolder, for: state)
        } else {
            setImage(Vincent.sharedInstance.retrieveCachedImage(url: url), for: state)
        }
        
        guard let url = url else {return}
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, requestModification: requestModification) { [weak self] image, error in
            guard let image = image else {
                DispatchQueue.main.async(execute: {
                    completion?(nil, error)
                })
                return
            }
        
            DispatchQueue.main.async(execute: {
                self?.setImage(image, for: state)
                completion?(image, nil)
            })
        }
    }
    
    func cancelImageDownload() {
        Vincent.sharedInstance.cancelDownload(identifier: self.downloadTaskIdentifier)
    }
    
    func invalidateImageDownload() {
        Vincent.sharedInstance.invalidateDownload(identifier: self.downloadTaskIdentifier)
    }
}
