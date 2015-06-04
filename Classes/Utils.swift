//
//  VincentUtils.swift
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
            objc_setAssociatedObject(self, &downloadTaskKey, newValue, objc_AssociationPolicy(OBJC_ASSOCIATION_RETAIN))
        }
    }
    
    func setImageWithString(urlString: String?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithString(urlString, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, placeHolder: UIImage?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, placeHolder: UIImage?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithString(urlString, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }

    func setImageWithString(urlString: String?, placeHolder: UIImage?, cacheType: CacheType, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        } else {
            setImageWithUrl(NSURL?(), placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        }
    }
    
    func setImageWithUrl(url: NSURL?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithUrl(url, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithUrl(url, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, placeHolder: UIImage?, cacheType: CacheType, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        let downloader = Vincent.sharedInstance
        downloader.invalidate(self.downloadTaskIdentifier)
        
        if let placeHolder = placeHolder {
            self.image = placeHolder
        } else {
            self.image = downloader.retrieveCachedImageForUrl(url)
        }
        
        if let url = url {
            self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, success: {[weak self] image in
                self?.downloadTaskIdentifier = nil
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self?.image = image
                    completion?(error: nil, image: image)
                })
                }, error: {[weak self] (error: NSError) -> () in
                    if error.code != -999 {
                        self?.downloadTaskIdentifier = nil
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            let _ = completion?(error: error, image: nil)
                        })
                    }
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
            return objc_getAssociatedObject(self, &downloadTaskKey) as! String?
        }
        set(newValue) {
            objc_setAssociatedObject(self, &downloadTaskKey, newValue, objc_AssociationPolicy(OBJC_ASSOCIATION_RETAIN))
        }
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithString(urlString, forState: state, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithString(urlString, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithString(urlString: String?, forState state: UIControlState, placeHolder: UIImage?, cacheType: CacheType, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        if let urlString = urlString {
            setImageWithUrl(NSURL(string: urlString), forState: state, placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        } else {
            setImageWithUrl(NSURL?(), forState: state, placeHolder: placeHolder, cacheType: cacheType, completion: completion)
        }
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, completion: ((error: NSError?, image: UIImage?) -> ())?) {
        setImageWithUrl(url, forState: state, placeHolder: nil, cacheType: .Automatic, completion: completion)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?) {
        setImageWithUrl(url, forState: state, placeHolder: placeHolder, cacheType: .Automatic, completion: nil)
    }
    
    func setImageWithUrl(url: NSURL?, forState state: UIControlState, placeHolder: UIImage?, completion: ((error: NSError?, image: UIImage?) -> ())?) {
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
        
        if let url = url {
            self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, success: {[weak self] image in
                self?.downloadTaskIdentifier = nil
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self?.setImage(image, forState: state)
                    completion?(error: nil, image: image)
                })
                }, error: {[weak self] (error: NSError) -> () in
                    if error.code != -999 {
                        self?.downloadTaskIdentifier = nil
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            let _ = completion?(error: error, image: nil)
                        })
                    }
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