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
import SCLAlertView

class ViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    
    @IBOutlet weak var messageBackground: UILabel!
    @IBOutlet weak var messageLabel:UILabel!
    @IBOutlet weak var refresh: UIImageView!
    @IBOutlet weak var picture: UIImageView!
    @IBOutlet weak var cameraIcon: UIImageView!
    @IBOutlet weak var leftArrow: UIImageView!

    var captureSession:AVCaptureSession?
    var videoPreviewLayer:AVCaptureVideoPreviewLayer?
    var qrCodeFrameView:UIView?
    
    @IBOutlet weak var placeQRHere: UIImageView!
    var qrCodeInView = false
    
    var url: String? // hrbot heroku url
    var checkedInUsers: Set<String> = [] // users already checked in; don't recheck them in!
    
    let defaultText = "Line up your QR code with the image below!"
    
    // Added to support different barcodes
    let supportedBarCodes = [AVMetadataObjectTypeQRCode, AVMetadataObjectTypeCode128Code, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeUPCECode, AVMetadataObjectTypePDF417Code, AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeAztecCode]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)

        // Get an instance of the AVCaptureDevice class to initialize a device object and provide the video
        // as the media type parameter.
//        let captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        let captureDevice = getCamera(AVCaptureDevicePosition.front);
        
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
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            // Detect all the supported bar code
            captureMetadataOutput.metadataObjectTypes = supportedBarCodes
            
            // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds

            view.layer.addSublayer(videoPreviewLayer!)
            
            // Start video capture
            captureSession?.startRunning()

            
            // Initialize QR Code Frame to highlight the QR code
            qrCodeFrameView = UIView()
            
            if let qrCodeFrameView = qrCodeFrameView {
                qrCodeFrameView.layer.borderColor = UIColor.green.cgColor
                qrCodeFrameView.layer.borderWidth = 2
                view.addSubview(qrCodeFrameView)
                view.bringSubview(toFront: qrCodeFrameView)
            }
            
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }

        
        let profileTap = UITapGestureRecognizer(target: self, action:#selector(ViewController.refreshUsers))
        refresh.isUserInteractionEnabled = true
        refresh.addGestureRecognizer(profileTap)
        view.bringSubview(toFront: refresh)
        

        view.bringSubview(toFront: placeQRHere)
        view.bringSubview(toFront: picture)
        view.bringSubview(toFront: messageBackground)
        view.bringSubview(toFront: messageLabel)
        view.bringSubview(toFront: cameraIcon)
        view.bringSubview(toFront: leftArrow)
        
        messageLabel.text = defaultText
        
    }
    

    // sclalertview has be to called here once the Window exists
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        
        
        if let array = UserDefaults.standard.value(forKey: "checkedInUsers") as? Set<String>, let date = UserDefaults.standard.value(forKey: "checkInDay") as? Date {
            let otherDay = NSCalendar.current.dateComponents([.era, .year, .month, .day], from: date)
            let today = NSCalendar.current.dateComponents([.era, .year, .month, .day], from: Date())
            
            if otherDay.era == today.era && otherDay.year == today.year && otherDay.month == today.month && otherDay.day == today.day {
                self.checkedInUsers = array
            }else{
                UserDefaults.standard.set(self.checkedInUsers, forKey: "checkedInUsers")
            }
        }else{
            UserDefaults.standard.set(Date(), forKey: "checkInDay")
        }
        
        // get url
        var keys: NSDictionary?
        if let path = Bundle.main.path(forResource: "secret", ofType: "plist") {
            keys = NSDictionary(contentsOfFile: path)
        }
        if let _ = keys {
            url  = keys?["hrbot_url"] as? String
        } else {
            SCLAlertView().showWarning("No URL for HRBot", subTitle: "No plist containing a URL for HRBot found. Check-ins won't get posted to Slack or update in the spreadsheet.")
            print("no hrbot url!")
        }
        
        if (!NetworkConnection.isConnectedToNetwork()) {
            SCLAlertView().showWarning("No network connection", subTitle: "Check-ins won't get posted to Slack or update in the spreadsheet.")
            print("no network connection!")
        }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        
        // Check if the metadataObjects array is not nil and it contains at least one object.
        if metadataObjects == nil || metadataObjects.count == 0 {
            qrCodeFrameView?.frame = CGRect.zero
            messageLabel.text = defaultText
            messageBackground.backgroundColor = UIColor(red: 170, green: 170, blue: 170, alpha: 0.5)
            qrCodeInView = false
//            updateImage(nil, show: false)
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
            let barCodeObject = videoPreviewLayer?.transformedMetadataObject(for: metadataObj)
            qrCodeFrameView?.frame = barCodeObject!.bounds
            
            // if this isn't the first time a qr code was in view then update message label and check user in
            if metadataObj.stringValue != nil && !qrCodeInView {
                messageLabel.text = "Hey " + metadataObj.stringValue + "!"
                messageBackground.backgroundColor = UIColor(red: 102, green: 187, blue: 106, alpha: 0.5)
                checkUserIntoHRBot(metadataObj.stringValue)
                qrCodeInView = true
            }
        }
    }
    
    func updateImage(_ response: String?, show: Bool) {
        if show {
            if let _ = response {
                
            } else {
                picture.alpha = 1.0
                picture.image = UIImage(named: "slack")
                UIView.animate(withDuration: 1, delay: 1, options: .curveEaseOut, animations: {
                    
                    self.picture.alpha = 0.0

                    }, completion: nil)
            }
            print("set image")
        } else {
            picture.image = nil
        }
    }
    
    func getCamera(_ position: AVCaptureDevicePosition) -> AVCaptureDevice {
        for device in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) {
            if (device as AnyObject).position == AVCaptureDevicePosition.front {
                return device as! AVCaptureDevice
            }
        }
        return AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
    }
    
    func getVideoOrientation(_ deviceOrientation: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        print(deviceOrientation.rawValue)
        if deviceOrientation.isPortrait {
            print("p")
            return AVCaptureVideoOrientation.portrait
        } else if deviceOrientation.isLandscape {
            print("ll")
            return AVCaptureVideoOrientation.landscapeLeft
        } else if deviceOrientation == UIDeviceOrientation.landscapeRight {
            print("lr")
            return AVCaptureVideoOrientation.landscapeRight
        } else {
            print("pu")
            return AVCaptureVideoOrientation.portraitUpsideDown
        }
    }
    
    // update video preview on rotation
    func rotated() {
        if (UIDevice.current.orientation == UIDeviceOrientation.portrait){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.portrait
        } else if (UIDevice.current.orientation == UIDeviceOrientation.portraitUpsideDown){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.portraitUpsideDown
        } else if (UIDevice.current.orientation == UIDeviceOrientation.landscapeRight){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.landscapeLeft

        } else if (UIDevice.current.orientation == UIDeviceOrientation.landscapeLeft){
            videoPreviewLayer?.connection.videoOrientation = AVCaptureVideoOrientation.landscapeRight

        }
        
        videoPreviewLayer?.frame = view.layer.bounds
    }

//    takes in the qr code string and attempts to decode it and send it to hr bot
    func checkUserIntoHRBot(_ string: String?) {
        var qr_data = [ // json data; default is error
            "username": "error"
        ]
        
        // attempt to add string to json; if already saw string then return
        if let string = string {
            if (checkedInUsers.contains(string)) {
                print("Already checked in \(string)\n")
                messageLabel.text = "Already checked you in " + string + "!"
                return
            } else {
                checkedInUsers.insert(string)
//                UserDefaults.standard.set(checkedInUsers, forKey: "checkedInUsers")
                qr_data = [ // json data
                    //            "username": "error"
                    "username": string
                ]
            }
        }
        
        // send POST
        if let _ = url {
//            Alamofire.request(.POST, url!, parameters: qr_data, encoding: .json)
            let _ = Alamofire.request(url!, method: .post, parameters: qr_data, encoding: JSONEncoding.default, headers: nil)
            updateImage(nil, show: true)
            print("sent POST with data \n\t\(qr_data) \nto url \n\t\(url)\n")
        } else {
            print("error: no url from secret.plist")
        }
    }
    
    func refreshUsers() {
        messageLabel.text = "I just reset who's checked in, go ahead and check in again!" // doesn't change the google doc, only what the app remembers!
        checkedInUsers = []
        qrCodeInView = false
    }
    
    override func viewWillLayoutSubviews() {
        videoPreviewLayer?.frame = view.frame
    }
}

