//
//  ViewController.swift
//  Scanner3DApp
//
//  Created by Macbook on 27/03/2021.
//

import UIKit
import ARKit
import SceneKit
class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    @IBOutlet weak var instructionLabel: MessageLabel!
    @IBOutlet var sceneView: ARSCNView!
    let shapeLayer = CAShapeLayer()
    let tapGesture = UITapGestureRecognizer()
    internal var internalState: State = .startARSession
    static var instance: ViewController?
    internal var scan: Scan?
    internal var screenCenter = CGPoint()
    
    var referenceObjectToTest: ARReferenceObject?
    var referenceObjectToMerge: ARReferenceObject?
    
    static let appStateChangedNotification = Notification.Name("ApplicationStateChanged")
    static let appStateUserInfoKey = "AppState"
    
    internal var testRun: TestRun?
    
    internal var messageExpirationTimer: Timer?
    internal var startTimeOfLastMessage: TimeInterval?
    internal var expirationTimeOfLastMessage: TimeInterval?
//    
//    var modelURL: URL? {
//        didSet {
//            if let url = modelURL {
//                displayMessage("3D model \"\(url.lastPathComponent)\" received.", expirationTime: 3.0)
//            }
//            if let scannedObject = self.scan?.scannedObject {
//                scannedObject.set3DModel(modelURL)
//            }
//            if let dectectedObject = self.testRun?.detectedObject {
//                dectectedObject.set3DModel(modelURL)
//            }
//        }
//    }
//    
//        
    
    
    override func viewWillAppear(_ animated: Bool) {
        let config = ARWorldTrackingConfiguration()
        sceneView.session.run(config)
        ViewController.instance = self
        
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        createProgressCircle()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(scanningStateChanged), name: Scan.stateChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasCreated),
                                       name: ScannedObject.ghostBoundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(ghostBoundingBoxWasRemoved),
                                       name: ScannedObject.ghostBoundingBoxRemovedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxWasCreated),
                                       name: ScannedObject.boundingBoxCreatedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(scanPercentageChanged),
                                       name: BoundingBox.scanPercentageChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
                                       name: BoundingBox.extentChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(boundingBoxPositionOrExtentChanged(_:)),
                                       name: BoundingBox.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(objectOriginPositionChanged(_:)),
                                       name: ObjectOrigin.positionChangedNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(displayWarningIfInLowPowerMode),
                                       name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        state = .startARSession
        
        
        
        
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Store the screen center location after the view's bounds did change,
        // so it can be retrieved later from outside the main thread.
        screenCenter = sceneView.center
    }
    

    @IBAction func endBtnNext(_ sender: Any) {
        switchToNextState()
    }
    
    fileprivate func createProgressCircle(){
        let position = UIView(frame: CGRect(x: view.bounds.width/2, y: view.bounds.height*4/5, width: 20, height: 20)).center
        let circularPath = UIBezierPath(arcCenter: position, radius: 20, startAngle: 0, endAngle: 2*CGFloat.pi, clockwise: true)
        shapeLayer.path = circularPath.cgPath
        shapeLayer.fillColor = UIColor.red.cgColor
        shapeLayer.strokeColor = UIColor.white.cgColor
        shapeLayer.lineWidth = 3
        shapeLayer.lineCap = .round
        shapeLayer.strokeEnd = 0
        
        view.layer.addSublayer(shapeLayer)
        
        self.view.addGestureRecognizer(tapGesture)
        tapGesture.addTarget(self, action: #selector(handleTap))
    }
    
    @objc private func handleTap(){
        let basicAnimation = CABasicAnimation(keyPath: "strokeEnd")
        basicAnimation.toValue = 1
        basicAnimation.duration = 2
        basicAnimation.fillMode = .forwards
        basicAnimation.isRemovedOnCompletion = false
        shapeLayer.add(basicAnimation, forKey: "urSoBasic")
        
    }
    
    func displayInstruction(_ message: Message) {
        instructionLabel.display(message)
//        instructionsVisible = true
    }

    func showAlert(title: String, message: String, buttonTitle: String? = "OK", showCancel: Bool = false, buttonHandler: ((UIAlertAction) -> Void)? = nil) {
        print(title + "\n" + message)
        
        var actions = [UIAlertAction]()
        if let buttonTitle = buttonTitle {
            actions.append(UIAlertAction(title: buttonTitle, style: .default, handler: buttonHandler))
        }
        if showCancel {
            actions.append(UIAlertAction(title: "Cancel", style: .cancel))
        }
        self.showAlert(title: title, message: message, actions: actions)
    }
    
    func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        let showAlertBlock = {
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach { alertController.addAction($0) }
            DispatchQueue.main.async {
                self.present(alertController, animated: true, completion: nil)
            }
        }
        
        if presentedViewController != nil {
            dismiss(animated: true) {
                showAlertBlock()
            }
        } else {
            showAlertBlock()
        }
    }
    
    @objc
    func scanPercentageChanged(_ notification: Notification) {
        guard let percentage = notification.userInfo?[BoundingBox.scanPercentageUserInfoKey] as? Int else { return }
        
        // Switch to the next state if the scan is complete.
        if percentage >= 100 {
            switchToNextState()
            return
        }
//        DispatchQueue.main.async {
//            self.setNavigationBarTitle("Scan (\(percentage)%)")
//        }
    }
    
    @objc
    func boundingBoxPositionOrExtentChanged(_ notification: Notification) {
        guard let box = notification.object as? BoundingBox,
            let cameraPos = sceneView.pointOfView?.simdWorldPosition else { return }
        
        let xString = String(format: "width: %.2f", box.extent.x)
        let yString = String(format: "height: %.2f", box.extent.y)
        let zString = String(format: "length: %.2f", box.extent.z)
        let distanceFromCamera = String(format: "%.2f m", distance(box.simdWorldPosition, cameraPos))
        displayMessage("Current bounding box: \(distanceFromCamera) away\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func objectOriginPositionChanged(_ notification: Notification) {
        guard let node = notification.object as? ObjectOrigin else { return }
        
        // Display origin position w.r.t. bounding box
        let xString = String(format: "x: %.2f", node.position.x)
        let yString = String(format: "y: %.2f", node.position.y)
        let zString = String(format: "z: %.2f", node.position.z)
        displayMessage("Current local origin position in meters:\n\(xString) \(yString) \(zString)", expirationTime: 1.5)
    }
    
    @objc
    func displayWarningIfInLowPowerMode() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            let title = "Low Power Mode is enabled"
            let message = "Performance may be impacted. For best scanning results, disable Low Power Mode in Settings > Battery, and restart the scan."
            let buttonTitle = "OK"
            self.showAlert(title: title, message: message, buttonTitle: buttonTitle, showCancel: false)
        }
    }
    
    override var shouldAutorotate: Bool {
        // Lock UI rotation after starting a scan
        if let scan = scan, scan.state != .ready {
            return false
        }
        return true
    }
}

