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
        
        numRequests++
        
        self.downloadTaskIdentifier = Vincent.sharedInstance.downloadImageFromUrl(url, cacheType: cacheType, success: {[weak self] image in
            self?.downloadTaskIdentifier = nil
            dispatch_async(dispatch_get_main_queue(), {
                self?.image = image
                if let vincentImageView = self as? VincentImageView where vincentImageView.showsSpinner {
                    vincentImageView.activityIndicator.stopAnimating()
                }
                completion?(error: nil, image: image)
            })
        }, error: {[weak self] error in
            if error.code != -999 {
                self?.downloadTaskIdentifier = nil
                dispatch_async(dispatch_get_main_queue(), {
                    completion?(error: error, image: nil)
                })
            }
        }, requestDone: {
            dispatch_async(dispatch_get_main_queue()) {
                if let vincentImageView = self as? VincentImageView where vincentImageView.showsSpinner {
                    self.numRequests--
                }
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

public class VincentImageView: UIImageView {
    @IBInspectable public var showsSpinner: Bool = true
    @IBInspectable public var showsSpinnerOnPlaceholder: Bool = false
    @IBInspectable public var spinnerSize: CGFloat = 50.0 {
        didSet {
            spinnerHeightConstraint?.constant = spinnerSize
            spinnerWidthConstraint?.constant = spinnerSize
        }
    }
    @IBInspectable public var spinnerTintColor: UIColor {
        set {
            activityIndicator.tintColor = newValue
        }
        get {
            return activityIndicator.tintColor
        }
    }
    @IBInspectable public var spinnerBackgroundColor: UIColor {
        set {
            activityIndicator.backgroundColor = newValue
        }
        get {
            return activityIndicator.backgroundColor ?? UIColor.clearColor()
        }
    }
    
    @IBInspectable public var spinnerLineWidth: CGFloat = 1.0 {
        didSet {
            activityIndicator.lineWidth = spinnerLineWidth
        }
    }
    
    @IBInspectable public var spinnerCornerRadius: CGFloat = 0.0 {
        didSet {
            activityIndicator.layer.cornerRadius = spinnerCornerRadius
        }
    }
    
    public private(set) var activityIndicator = ActivityIndicatorView()
    private var spinnerHeightConstraint: NSLayoutConstraint? = nil
    private var spinnerWidthConstraint: NSLayoutConstraint? = nil
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    public init() {
        super.init(frame: CGRect.zero)
        setup()
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    private func setup() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        
        spinnerWidthConstraint = NSLayoutConstraint(item: activityIndicator, attribute: .Width, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1, constant: spinnerSize)
        spinnerHeightConstraint = NSLayoutConstraint(item: activityIndicator, attribute: .Height, relatedBy: .Equal, toItem: nil, attribute: .NotAnAttribute, multiplier: 1, constant: spinnerSize)
        addConstraints([spinnerWidthConstraint!, spinnerHeightConstraint!])
        addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .CenterX, relatedBy: .Equal, toItem: self, attribute: .CenterX, multiplier: 1, constant: 0))
        addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .CenterY, relatedBy: .Equal, toItem: self, attribute: .CenterY, multiplier: 1, constant: 0))
    }
}

public class FadeInImageView: VincentImageView {
    private var fadeInDone: Bool = false
    private var fadeInInProgress: Bool = false
    @IBInspectable public var fadeInDuration: Double = 0.2
    
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

public class ActivityIndicatorView: UIView {
    @IBInspectable public var lineWidth: CGFloat = 1.0 {
        didSet {
            shapeLayer?.lineWidth = lineWidth
        }
    }
    public private(set) var isAnimating = false
    private var shapeLayer: CAShapeLayer?
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    public init() {
        super.init(frame: CGRect.zero)
        setup()
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    private func setup() {
        hidden = true
        let shapeLayer = CAShapeLayer()
        shapeLayer.borderWidth = 0
        shapeLayer.fillColor = UIColor.clearColor().CGColor
        shapeLayer.strokeColor = tintColor.CGColor
        shapeLayer.lineWidth = lineWidth
        layer.addSublayer(shapeLayer)
        self.shapeLayer = shapeLayer
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer?.frame = bounds
        shapeLayer?.path = self.layoutPath().CGPath
    }
    
    public override func tintColorDidChange() {
        super.tintColorDidChange()
        shapeLayer?.strokeColor = tintColor.CGColor
    }
    
    private func layoutPath() -> UIBezierPath {
        let twoPi = M_PI * 2.0
        let startAngle = CGFloat(0.75 * twoPi)
        let endAngle = CGFloat(startAngle + CGFloat(twoPi * 0.9))
        let width = bounds.width
        return UIBezierPath(arcCenter: CGPoint(x: width / 2.0, y: width / 2.0), radius: (width - 6) / 2.2, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    }
    
    public func startAnimating() {
        if !isAnimating {
            isAnimating = true
            let animation = CABasicAnimation(keyPath: "transform.rotation")
            animation.toValue = 2 * M_PI
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            animation.duration = 1.0
            animation.repeatCount = Float.infinity
            shapeLayer?.addAnimation(animation, forKey: "spinner")
        }
        hidden = false
    }
    
    public func stopAnimating() {
        isAnimating = false
        shapeLayer?.removeAnimationForKey("spinner")
        hidden = true
    }
}
