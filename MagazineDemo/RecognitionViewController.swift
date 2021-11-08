import UIKit
import AVFoundation
import Vision

class RecognitionViewController: ViewController {

    private var detectionOverlay: CALayer! = nil
    
    private var requests = [VNRequest]()
    
    override func viewDidLayoutSubviews() {
        self.configureVideoOrientation()
    }
    
    private func configureVideoOrientation() {
        if let previewLayer = self.previewLayer,
            let connection = previewLayer.connection {
            let orientation = UIDevice.current.orientation
            print("Configuring video orientation, device = \(getDeviceOrientationName(orientation))")

            if connection.isVideoOrientationSupported,
                let videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) {
                previewLayer.frame = self.view.bounds
                connection.videoOrientation = videoOrientation
            }
        }
    }
    
    /*
    private func updatePreviewLayer(layer: AVCaptureConnection, orientation: AVCaptureVideoOrientation) {
        layer.videoOrientation = orientation
        previewLayer.frame = self.view.bounds
    }
    */
    
    @discardableResult
    func setupVision() -> NSError? {
        let error: NSError! = nil
        
        let modelName = "bitti-2021-03-24-18-03-32"
        
        /*
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = .cpuAndGPU
        */
        
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return NSError(domain: "RecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        
        do {
            //let model = try! MLModel(contentsOf: modelURL, configuration: modelConfiguration)
            let model = try! MLModel(contentsOf: modelURL)
            
            // Print out some information about the Core ML model
            let modelDescription = model.modelDescription
            if let featureName = modelDescription.predictedFeatureName {
                print("Model predicts a single feature: '\(featureName)'")
            }
            else {
                print("Inputs: \(modelDescription.inputDescriptionsByName)")
                print("Outputs: \(modelDescription.outputDescriptionsByName)")
                
                // There are no image outputs, so the observations should be VNCoreMLFeatureValueObservation objects?
            }
            
            if let labels = modelDescription.classLabels {
                print("Class labels:")
                for label in labels {
                    print(label)
                }
            }
            
            let visionModel = try VNCoreMLModel(for: model)
            print("Vision model info: inputImageFeatureName = \(visionModel.inputImageFeatureName)")

            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                //print("Request type = \(type(of: request))")
                //print("Processing recognition request: \(request)")
                if let results = request.results {
                    //print("Request result count = \(results.count)")

                    for result in results {
                        print(result)
                    }
                }
                else {
                    print("Recognition request had no results")
                }

                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        for result in results {
                            print(result)
                        }
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            
            // Setting this has no effect on portrait/landscape
            objectRecognition.imageCropAndScaleOption = .scaleFill
            
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading failed: \(error)")
        }
        
        return error
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                print("Not a recognized object observation: \(observation)")
                continue
            }
            //print(objectObservation)
         
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]

            print("Observed: \(topLabelObservation.identifier), confidence = \(topLabelObservation.confidence), bbox = \(objectObservation.boundingBox)")

            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print("capture output called")
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        //let cgImage = CGImage.create(pixelBuffer: pixelBuffer)
        //let grayPixelBuffer = (cgImage?.pixelBufferGray())!
        
        //let originalImage = CIImage(cvPixelBuffer: pixelBuffer, options: [CIImageOption.colorSpace: NSNull()])
        /*
        guard let filteredImage = filter.outputImage else {
            return
        }
        */
        
        let deviceOrientation = UIDevice.current.orientation
        let exifOrientation = self.exifOrientationFromDeviceOrientation()
        //print("Device orientation = \(getDeviceOrientationName(deviceOrientation)), EXIF orientation = \(getExifOrientationName(exifOrientation))")
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    public override func exifOrientationFromDeviceOrientation() -> CGImagePropertyOrientation {
        let curDeviceOrientation = UIDevice.current.orientation
        let exifOrientation: CGImagePropertyOrientation
        
        switch curDeviceOrientation {
        case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = .left
        case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, home button on the right
            exifOrientation = .left
        case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, home button on the left
            exifOrientation = .left
        case UIDeviceOrientation.portrait:            // Device oriented vertically, home button on the bottom
            exifOrientation = .up
        default:
            exifOrientation = .up
        }
        return exifOrientation
    }

    private func getDeviceOrientationName(_ orientation: UIDeviceOrientation) -> String {
        var s = ""

        switch orientation {
        case .unknown:
            s = "unknown"
        case .portrait:
            s = "portrait"
        case .portraitUpsideDown:
            s = "portrait upside down"
        case .landscapeLeft:
            s = "landscape left"
        case .landscapeRight:
            s = "landscape right"
        case .faceUp:
            s = "face up"
        case .faceDown:
            s = "face down"
        }

        return s
    }
    
    private func getExifOrientationName(_ orientation: CGImagePropertyOrientation) -> String {
        var s = ""
        
        switch orientation {
        case .up:
            s = "up"
        case .upMirrored:
            s = "up, mirrored"
        case .down:
            s = "down"
        case .downMirrored:
            s = "down, mirrored"
        case .leftMirrored:
            s = "left, mirrored"
        case .left:
            s = "left"
        case .rightMirrored:
            s = "right, mirrored"
        case .right:
            s = "right"
        }
        
        return s
    }
    
    override func setupAVCapture() {
        super.setupAVCapture()
        
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        startCaptureSession()
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    func rotateRect(_ rect: CGRect) -> CGRect {
        let x = rect.midX
        let y = rect.midY
        let transform = CGAffineTransform(translationX: x, y: y)
                                        .rotated(by: .pi / 2)
                                        .translatedBy(x: -x, y: -y)
        return rect.applying(transform)
    }
    
    func increaseRect(rect: CGRect, byPercentage percentage: CGFloat) -> CGRect {
        let startWidth = rect.width
        let startHeight = rect.height
        let adjustmentWidth = (startWidth * percentage) / 2.0
        let adjustmentHeight = (startHeight * percentage) / 2.0
        return rect.insetBy(dx: -adjustmentWidth, dy: -adjustmentHeight)
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        var finalBounds = rotateRect(bounds)
        //var finalBounds = bounds
        finalBounds = increaseRect(rect: finalBounds, byPercentage: 0.2)
        print("T layer:\nbounds = \(bounds)\nrotated = \(finalBounds)")

        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let confidencePercentage = String(format: "%d", Int(confidence * 100))
        let formattedString = NSMutableAttributedString(string: "\(identifier) \(confidencePercentage)%")
        //let formattedString = NSMutableAttributedString(string: String(format: "\(identifier) Confidence: %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: finalBounds.size.height - 10, height: finalBounds.size.width - 10)
        textLayer.position = CGPoint(x: finalBounds.midX - 5, y: finalBounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        var finalBounds = rotateRect(bounds)
        //var finalBounds = bounds
        finalBounds = increaseRect(rect: finalBounds, byPercentage: 0.2)
        print("RR layer:\nbounds = \(bounds)\nrotated = \(finalBounds)")

        let shapeLayer = CALayer()
        shapeLayer.bounds = finalBounds
        shapeLayer.position = CGPoint(x: finalBounds.midX, y: finalBounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
}
