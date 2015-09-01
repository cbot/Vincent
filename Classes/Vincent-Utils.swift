//
//  Vincent-Utils.swift
//
//  Created by Kai Straßmann

import UIKit
import ObjectiveC

private var downloadTaskKey: UInt8 = 0

public extension UIImageView {
    var downloadTaskIdentifier: String? {
        get {
            return objc_getAssociatedObject(self, &downloadTaskKey) as! String?
        }
        set(newValue) {
            objc_setAssociatedObject(self, &downloadTaskKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN)
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

    func setImageWithString(urlString: String?, placeHolder: UIImage?, cacheType: CacheType, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        } else {
            setImageWithUrl(NSURL?(), placeHolder: placeHolder, cacheType: cacheType, completion: completion)
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
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?, cacheType: CacheType, completion: CompletionClosure?) {
        let downloader = Vincent.sharedInstance
        downloader.invalidate(self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            self.image = placeHolder
        } else {
            self.image = downloader.retrieveCachedImageForUrl(url)
        }
        
        guard let url = url else {return}
        
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, success: {[weak self] image in
            self?.downloadTaskIdentifier = nil
            dispatch_async(dispatch_get_main_queue(), {
                self?.image = image
                completion?(error: nil, image: image)
            })
        }, error: {[weak self] error in
            if error.code != -999 {
                self?.downloadTaskIdentifier = nil
                dispatch_async(dispatch_get_main_queue(), {
                    completion?(error: error, image: nil)
                })
            }
        })
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
            return objc_getAssociatedObject(self, &downloadTaskKey) as! String?
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
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, completion: CompletionClosure?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), forState: state, placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        } else {
            setImageWithUrl(NSURL?(), forState: state, placeHolder: placeHolder, cacheType: cacheType, completion: completion)
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
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        let downloader = Vincent.sharedInstance
        downloader.invalidate(self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            setImage(placeHolder, forState: state)
        } else {
            setImage(downloader.retrieveCachedImageForUrl(url), forState: state)
        }
        
        guard let url = url else {return}
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, success: {[weak self] image in
            self?.downloadTaskIdentifier = nil
            dispatch_async(dispatch_get_main_queue(), {
                self?.setImage(image, forState: state)
                completion?(error: nil, image: image)
            })
        }, error: {[weak self] error in
            if error.code != -999 {
                self?.downloadTaskIdentifier = nil
                dispatch_async(dispatch_get_main_queue(), {
                    completion?(error: error, image: nil)
                })
            }
        })
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

public class FadeInImageView: UIImageView {
    private var fadeInDone: Bool = false
    private var fadeInInProgress: Bool = false
    @IBInspectable var fadeInDuration: Double = 0.2
    
    override public var image: UIImage? {
    
        willSet {
            if !fadeInDone && newValue != nil {
                fadeInDone = true
                
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.duration = fadeInDuration
                animation.fromValue = 0
                animation.toValue = 1
                animation.fillMode = kCAFillModeBoth
                
                layer.addAnimation(animation, forKey: "fadeIn")
            }
        }
    }
}
