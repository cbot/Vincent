import UIKit

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
            return activityIndicator.backgroundColor ?? UIColor.clear
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
        
        spinnerWidthConstraint = NSLayoutConstraint(item: activityIndicator, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: spinnerSize)
        spinnerHeightConstraint = NSLayoutConstraint(item: activityIndicator, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: spinnerSize)
        
        addConstraints([spinnerWidthConstraint, spinnerHeightConstraint].flatMap({$0}))
        
        addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerX, relatedBy: .equal, toItem: self, attribute: .centerX, multiplier: 1, constant: 0))
        addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerY, relatedBy: .equal, toItem: self, attribute: .centerY, multiplier: 1, constant: 0))
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
                
                layer.add(animation, forKey: "fadeIn")
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
        isHidden = true
        let shapeLayer = CAShapeLayer()
        shapeLayer.borderWidth = 0
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = tintColor.cgColor
        shapeLayer.lineWidth = lineWidth
        layer.addSublayer(shapeLayer)
        self.shapeLayer = shapeLayer
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer?.frame = bounds
        shapeLayer?.path = self.layoutPath().cgPath
    }
    
    public override func tintColorDidChange() {
        super.tintColorDidChange()
        shapeLayer?.strokeColor = tintColor.cgColor
    }
    
    private func layoutPath() -> UIBezierPath {
        let twoPi = M_PI * 2.0
        let startAngle = CGFloat(0.75 * twoPi)
        let endAngle = CGFloat(startAngle + CGFloat(twoPi * 0.9))
        let width = bounds.width
        return UIBezierPath(arcCenter: CGPoint(x: width / 2.0, y: width / 2.0), radius: (width - 6) / 2.2, startAngle: startAngle, endAngle: endAngle, clockwise: true)
    }
    
    public func startAnimating() {
        if shapeLayer?.animation(forKey: "spinner") == nil {
            let animation = CABasicAnimation(keyPath: "transform.rotation")
            animation.toValue = 2 * M_PI
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            animation.duration = 1.0
            animation.repeatCount = Float.infinity
            shapeLayer?.add(animation, forKey: "spinner")
        }
        isAnimating = true
        isHidden = false
    }
    
    public func stopAnimating() {
        isAnimating = false
        shapeLayer?.removeAnimation(forKey: "spinner")
        isHidden = true
    }
}
