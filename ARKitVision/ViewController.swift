/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the ARKitVision sample.
*/

import UIKit
import SpriteKit
import ARKit
import Vision

class ViewController: UIViewController, UIGestureRecognizerDelegate, ARSKViewDelegate, ARSessionDelegate {
    
    @IBOutlet weak var sceneView: ARSKView!
    var qrCodeFrameView:UIView?
    
    // The view controller that displays the status and "restart experience" UI.
    private lazy var statusViewController: StatusViewController = {
        return children.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    // MARK: - View controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure and present the SpriteKit scene that draws overlay content.
        let overlayScene = SKScene()
        overlayScene.scaleMode = .aspectFill
        sceneView.delegate = self
        sceneView.presentScene(overlayScene)
        sceneView.session.delegate = self
        
        // Hook up status view controller callback.
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartSession()
        }
        
        // Initialize QR Code Frame to highlight the QR code
        qrCodeFrameView = UIView()
        if let qrCodeFrameView = qrCodeFrameView {
            qrCodeFrameView.layer.borderColor = UIColor.green.cgColor
            qrCodeFrameView.layer.borderWidth = 2
            view.addSubview(qrCodeFrameView)
            self.view.bringSubviewToFront(qrCodeFrameView)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    // MARK: - ARSessionDelegate
    
    // Pass camera frames received from ARKit to Vision (when not already processing one)
    /// - Tag: ConsumeARFrames
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Do not enqueue other buffers for processing while another Vision task is still running.
        // The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        // Retain the image buffer for Vision processing.
        self.currentBuffer = frame.capturedImage
        classifyCurrentImage()
    }
    
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    
    // Queue for dispatching vision classification requests
    private let visionQueue = DispatchQueue(label: "com.example.apple-samplecode.ARKitVision.serialVisionQueue")
    
    // Run the Vision+ML classifier on the current image buffer.
    /// - Tag: ClassifyCurrentImage
    private func classifyCurrentImage() {
        // Most computer vision tasks are not rotation agnostic so it is important to pass in the orientation of the image with respect to device.
        let orientation = CGImagePropertyOrientation(UIDevice.current.orientation)
        
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: { request, error in
            self.reportResults(results: request.results)
        })
        let handler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, options: [.properties : ""])
        
//        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: orientation)
        
        visionQueue.async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentBuffer = nil }
//                try requestHandler.perform([self.classificationRequest])
                try handler.perform([barcodeRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    private func reportResults(results: [Any]?) {
        
        // Loop through the found results
        print("Barcode observation")
        
        guard let results = results else {
            return print("No results found.")
        }
        
        print("Number of results found: \(results.count)")
        identifierString = ""
        if( results.count > 0){
            for result in results {
                if let barcode = result as? VNBarcodeObservation {
                    if let payload = barcode.payloadStringValue {
                        //                    print("Payload: \(payload)")
                        identifierString = payload;
                    }
                }
                if let bbox = result as? VNRectangleObservation{
//                    qrCodeFrameView?.frame = bbox.boundingBox
                    print(bbox.boundingBox)
                }
            }
        }else{
            qrCodeFrameView?.frame = CGRect.zero
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.displayClassifierResults()
        }
    }
    
    
    // Classification results
    private var identifierString = ""
    private var confidence: VNConfidence = 0.0
    
    
    // Show the classification results in the UI.
    private func displayClassifierResults() {
        guard !self.identifierString.isEmpty else {
            return // No object was classified.
        }
//        let message = String(format: "Detected \(self.identifierString) with %.2f", self.confidence * 100) + "% confidence"
        let message = String("QR code detected")
        statusViewController.showMessage(message)
    }
    
    // MARK: - Tap gesture handler & ARSKViewDelegate
    
    // Labels for classified objects by ARAnchor UUID
    private var anchorLabels = [UUID: String]()
    
    // When the user taps, add an anchor associated with the current classification result.
    /// - Tag: PlaceLabelAtLocation
    @IBAction func placeLabelAtLocation(sender: UITapGestureRecognizer) {
        let hitLocationInView = sender.location(in: sceneView)
        let hitTestResults = sceneView.hitTest(hitLocationInView, types: [.featurePoint, .estimatedHorizontalPlane])
        if let result = hitTestResults.first {
            
            // Add a new anchor at the tap location.
            let anchor = ARAnchor(transform: result.worldTransform)
            sceneView.session.add(anchor: anchor)
            
            // Track anchor ID to associate text with the anchor after ARKit creates a corresponding SKNode.
            anchorLabels[anchor.identifier] = identifierString
        }
    }
    
    // When an anchor is added, provide a SpriteKit node for it and set its text to the classification label.
    /// - Tag: UpdateARContent
    func view(_ view: ARSKView, didAdd node: SKNode, for anchor: ARAnchor) {
        guard let labelText = anchorLabels[anchor.identifier] else {
            fatalError("missing expected associated label for anchor")
        }
        
//        let background = SKSpriteNode(color: UIColor.red, size: CGSize(width: CGFloat(0.3), height:CGFloat(0.3)))
        let background = SKSpriteNode(color: UIColor.red, size: CGSize(width: 0, height: 0))

        background.position = node.position;//CGPoint(x: CGFloat(200), y: CGFloat(100))
        background.zPosition = 1
        
        node.addChild(background)
        let label = TemplateLabelNode(text: labelText)
        background.addChild(label);
        background.size = CGSize(width: CGFloat(label.frame.size.width), height:CGFloat(label.frame.size.height))
    }
    
    // MARK: - AR Session Handling
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
        switch camera.trackingState {
        case .notAvailable, .limited:
            statusViewController.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            statusViewController.cancelScheduledMessage(for: .trackingStateEscalation)
            // Unhide content after successful relocalization.
            setOverlaysHidden(false)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Filter out optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        setOverlaysHidden(true)
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        /*
         Allow the session to attempt to resume after an interruption.
         This process may not succeed, so the app must be prepared
         to reset the session if the relocalizing status continues
         for a long time -- see `escalateFeedback` in `StatusViewController`.
         */
        return true
    }

    private func setOverlaysHidden(_ shouldHide: Bool) {
        sceneView.scene!.children.forEach { node in
            if shouldHide {
                // Hide overlay content immediately during relocalization.
                node.alpha = 0
            } else {
                // Fade overlay content in after relocalization succeeds.
                node.run(.fadeIn(withDuration: 0.5))
            }
        }
    }

    private func restartSession() {
        statusViewController.cancelAllScheduledMessages()
        statusViewController.showMessage("RESTARTING SESSION")

        anchorLabels = [UUID: String]()
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Error handling
    
    private func displayErrorMessage(title: String, message: String) {
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.restartSession()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
}
