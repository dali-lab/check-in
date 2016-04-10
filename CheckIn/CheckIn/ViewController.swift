//
//  ViewController.swift
//  CheckIn
//
//  Created by Patrick Xu on 3/28/16.
//  Copyright © 2016 DALI. All rights reserved.
//
//  Code snippet by Simon Ng from AppCoda
//

import UIKit
import AVFoundation
import Alamofire

class ViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    @IBOutlet weak var messageLabel:UILabel!
    @IBOutlet weak var refresh: UIImageView!

    var captureSession:AVCaptureSession?
    var videoPreviewLayer:AVCaptureVideoPreviewLayer?
    var qrCodeFrameView:UIView?
    
    var qrCodeInView = false
    
    var url: String? // hrbot heroku url
    var checkedInUsers: Set<String> = [] // users already checked in; don't recheck them in!
    
    // Added to support different barcodes
    let supportedBarCodes = [AVMetadataObjectTypeQRCode, AVMetadataObjectTypeCode128Code, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeUPCECode, AVMetadataObjectTypePDF417Code, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeAztecCode]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Get an instance of the AVCaptureDevice class to initialize a device object and provide the video
        // as the media type parameter.
        let captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)

            // Initialize the captureSession object.
            captureSession = AVCaptureSession()
            // Set the input device on the capture session.
            captureSession?.addInput(input)

            // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession?.addOutput(captureMetadataOutput)
            
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: dispatch_get_main_queue())

            // Detect all the supported bar code
            captureMetadataOutput.metadataObjectTypes = supportedBarCodes
            
            // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ViewController.rotated), name: UIDeviceOrientationDidChangeNotification, object: nil)

            
            view.layer.addSublayer(videoPreviewLayer!)
            
            // Start video capture
            captureSession?.startRunning()
            
            // Move the message label to the top view
            view.bringSubviewToFront(messageLabel)
            
            // Initialize QR Code Frame to highlight the QR code
            qrCodeFrameView = UIView()
            
            if let qrCodeFrameView = qrCodeFrameView {
                qrCodeFrameView.layer.borderColor = UIColor.greenColor().CGColor
                qrCodeFrameView.layer.borderWidth = 2
                view.addSubview(qrCodeFrameView)
                view.bringSubviewToFront(qrCodeFrameView)
            }
            
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }
        
        var keys: NSDictionary?
        if let path = NSBundle.mainBundle().pathForResource("secret", ofType: "plist") {
            keys = NSDictionary(contentsOfFile: path)
        }
        
        // send message
        if let _ = keys {
            url  = keys?["hrbot_url"] as? String
        } else {
            print("no hrbot url!")
        }
        
        let profileTap = UITapGestureRecognizer(target: self, action:#selector(ViewController.refreshUsers))
        refresh.userInteractionEnabled = true
        refresh.addGestureRecognizer(profileTap)
        view.bringSubviewToFront(refresh)
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!) {
        
        // Check if the metadataObjects array is not nil and it contains at least one object.
        if metadataObjects == nil || metadataObjects.count == 0 {
            qrCodeFrameView?.frame = CGRectZero
            messageLabel.text = "Ready to check users in!"
            qrCodeInView = false
            return
        }
        
        // Get the metadata object.
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        // Here we use filter method to check if the type of metadataObj is supported
        // Instead of hardcoding the AVMetadataObjectTypeQRCode, we check if the type
        // can be found in the array of supported bar codes.
        if supportedBarCodes.contains(metadataObj.type) {
//        if metadataObj.type == AVMetadataObjectTypeQRCode {
            // If the found metadata is equal to the QR code metadata then update the status label's text and set the bounds
            let barCodeObject = videoPreviewLayer?.transformedMetadataObjectForMetadataObject(metadataObj)
            qrCodeFrameView?.frame = barCodeObject!.bounds
            
            // if this isn't the first time a qr code was in view then update message label and check user in
            if metadataObj.stringValue != nil && !qrCodeInView {
                messageLabel.text = metadataObj.stringValue
                checkUserIntoHRBot(metadataObj.stringValue)
                qrCodeInView = true
            }
        }
    }
    
    func getVideoOrientation(deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        print(deviceOrientation.rawValue)
        if deviceOrientation.isPortrait {
            print("p")
            return AVCaptureVideoOrientation.Portrait
        } else if deviceOrientation.isLandscape {
            print("ll")
            return AVCaptureVideoOrientation.LandscapeLeft
        } else if deviceOrientation == UIDeviceOrientation.LandscapeRight {
            print("lr")
            return AVCaptureVideoOrientation.LandscapeRight
        } else {
            print("pu")
            return AVCaptureVideoOrientation.PortraitUpsideDown
        }
    }
    
    // update video preview on rotation
    func rotated() {
        if (UIDevice.currentDevice().orientation == UIDeviceOrientation.Portrait){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.Portrait
        } else if (UIDevice.currentDevice().orientation == UIDeviceOrientation.PortraitUpsideDown){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.PortraitUpsideDown
        } else if (UIDevice.currentDevice().orientation == UIDeviceOrientation.LandscapeRight){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.LandscapeLeft

        } else if (UIDevice.currentDevice().orientation == UIDeviceOrientation.LandscapeLeft){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.LandscapeRight

        }
        
        videoPreviewLayer?.frame = view.layer.bounds
        print(videoPreviewLayer?.connection.videoScaleAndCropFactor)
    }

//    takes in the qr code string and attempts to decode it and send it to hr bot
    func checkUserIntoHRBot(string: String?) {
        var qr_data = [ // json data; default is error
            "username": "error"
        ]
        
        // attempt to add string to json; if already saw string then return
        if let _ = string {
            if (checkedInUsers.contains(string!)) {
                print("Already checked in \(string)\n")
                messageLabel.text = "Already checked in " + messageLabel.text!
                return
            } else {
                checkedInUsers.insert(string!)
                qr_data = [ // json data
                    //            "username": "error"
                    "username": string!
                ]
            }
        }

//        if let _ = string {
//            do {
//                // example json string
//                // var jsonStr = "{\"weather\":[{\"id\":804,\"main\":\"Clouds\",\"description\":\"overcast clouds\",\"icon\":\"04d\"}],}"
//                let data = string!.dataUsingEncoding(NSASCIIStringEncoding, allowLossyConversion: false)
//                let json: AnyObject! = try NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.MutableContainers)
//                if let _ = json["username"] as? String {
//                    qr_data["username"] = "1"
//                }
//            } catch {
//                print("error serializing JSON: \(error)")
//            }
//        }
        
        if let _ = url {
            Alamofire.request(.POST, url!, parameters: qr_data, encoding: .JSON)
            print("sent POST with data \n\t\(qr_data) \nto url \n\t\(url)\n")
        } else {
            print("error: no url from secret.plist")
        }
    }
    
    func refreshUsers() {
        messageLabel.text = "Ready to check people in!"
        checkedInUsers = []
        qrCodeInView = false
    }
}

