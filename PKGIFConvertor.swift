//
//  PKGIFConvertor.swift
//  PKGIFConvertorDemo
//
//  Created by Pramod Kumar on 8/9/17.
//  Copyright © 2017 Pramod Kumar. All rights reserved.
//

import Foundation
import AVFoundation
import ImageIO

class PKGIFConvertor: NSObject {
    
    //MARK:- Shared Instance
    //MARK:-
    public static var shared = PKGIFConvertor()
    
    //MARK:- Private Properties
    //MARK:-
    fileprivate var videoWriter: AVAssetWriter?
    fileprivate var buffer:NSMutableData = NSMutableData()
    fileprivate var session:URLSession?
    fileprivate var dataTask:URLSessionDataTask?
    fileprivate var expectedContentLength: Int = 0
    fileprivate var pregress: CGFloat = 0.0 {
        didSet {
            self.sendProgress(pregress: self.pregress)
        }
    }
    
    fileprivate let downloadedVideoPath: String = {
        let fileManager = FileManager.default
        let path = NSHomeDirectory().appending("/Documents/GIFConvertor")
        var directory = ObjCBool(true)
        if !fileManager.fileExists(atPath: path, isDirectory: &directory) {
            do{
                _ = try fileManager.createDirectory(atPath: path, withIntermediateDirectories: false, attributes: nil)
            }
            catch{
                Globals.printlnDebug("File path not created")
            }
        }
        return path
    }()
    
    fileprivate var videoPath: String = ""
    
    
    //MARK:- Complition Handler
    //MARK:-
    var complitionHandler: ((_ videoPath: String?, _ errorMessage: String?) -> Void)? = nil
    var progressHandler: ((_ progress: CGFloat) -> Void)? = nil
    
    
    //MARK:- Initializer
    //MARK:-
    //making initializer as private for not to create another object
    private override init() { }
    
    
    //MARK:- Public Methods
    //MARK:-
    func cancelConverting() {
        self.dataTask?.cancel()
        self.session?.invalidateAndCancel()
        self.dataTask = nil
        self.session = nil
        
        self.videoWriter?.cancelWriting()
        
        if FileManager.default.fileExists(atPath: self.videoPath) {
            try? FileManager.default.removeItem(atPath: self.videoPath)
        }
    }
    
    func convertGIFToVideo(gifPath: String, progress: @escaping((_ progress: CGFloat) -> Void) , completion: @escaping (_ videoPath: String?, _ errorMessage: String?) -> Void) {
        self.complitionHandler = completion
        self.progressHandler = progress
        self.buffer = NSMutableData()
        let configuration = URLSessionConfiguration.default
        let manqueue = OperationQueue.main
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: manqueue)
        self.dataTask = session?.dataTask(with: URLRequest(url: URL(string: gifPath)!))
        self.videoPath = self.downloadedVideoPath.appending("/download_video_\(Int(Date().timeIntervalSince1970)).mov")
        self.dataTask?.resume()
    }
    
    func convertGIFToVideo(gif: Data, movieSpeed: Float = 1.0, size: CGSize, repeatCount: Int = 1, output path: String, completion: @escaping (_ succes: Bool, _ errorMessage: String?) -> Void) {
        
        func handelComplition(withError: String, onLineNo: Int = #line, inFile: String = #file) {
            DispatchQueue.main.async(execute: {
                completion(false, "Error: \(withError), at line no \(onLineNo) in file \(inFile)")
            })
            return
        }
        
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async(execute: {
            //if file exist on output url return the process
            if FileManager.default.fileExists(atPath: path) {
                handelComplition(withError: "Output file already exists")
            }
            
            let gifData: [String:AnyObject] = self.loadGIFData(data: gif, resize: size, repeatCount: repeatCount)
            if let allFrames = gifData["frames"] as? [AnyObject], let first = allFrames.first as? UIImage {
                
                var frameSize = first.size
                frameSize.width = round(frameSize.width / 16) * 16
                frameSize.height = round(frameSize.height / 16) * 16
                do {
                    self.videoWriter = try AVAssetWriter(url: URL(fileURLWithPath: path), fileType: AVFileTypeMPEG4)
                }
                catch let error {
                    handelComplition(withError: error.localizedDescription)
                }
                
                //output video settings
                let videoSettings: [String : Any] = [
                    AVVideoCodecKey : AVVideoCodecH264,
                    AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
                    AVVideoWidthKey : Int(frameSize.width),
                    AVVideoHeightKey : Int(frameSize.height)
                    ] as [String : Any]
                
                
                let writerInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)
                var attributes = [String : Any]()
                attributes[kCVPixelBufferPixelFormatTypeKey as String] = Int(kCVPixelFormatType_32ARGB)
                attributes[kCVPixelBufferWidthKey as String] = Int(frameSize.width)
                attributes[kCVPixelBufferHeightKey as String] = Int(frameSize.height)
                
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: attributes)
                
                self.videoWriter?.add(writerInput)
                writerInput.expectsMediaDataInRealTime = true
                self.videoWriter?.startWriting()
                self.videoWriter?.startSession(atSourceTime: kCMTimeZero)
                var buffer: CVPixelBuffer? = nil
                buffer = self.pixelBufferFromCGImage(image: first.cgImage!, size: frameSize)
                let result = adaptor.append(buffer!, withPresentationTime: kCMTimeZero)
                if result == false {
                    print("Failed to append buffer")
                }
                
                let aniTime = (gifData["animationTime"] as? Int) ?? 0
                let fps = Float(allFrames.count) / (Float(aniTime) * movieSpeed)
                
                var i = 0
                
                //progress calulation
                let pregressPerImg = (1.0 - self.pregress) / CGFloat(allFrames.count)
                while i < allFrames.count {
                    if adaptor.assetWriterInput.isReadyForMoreMediaData {
                        if let image = allFrames[i] as? UIImage, let buffer = self.pixelBufferFromCGImage(image: image.cgImage!, size: frameSize) {
                            let frameTime = CMTimeMake(1, Int32(fps))
                            let lastTime = CMTimeMake(Int64(i), Int32(fps))
                            let presentTime = CMTimeAdd(lastTime, frameTime)
                            
                            let result = adaptor.append(buffer, withPresentationTime: presentTime)
                            if result == false {
                                print("Failed to append buffer: \(String(describing: self.videoWriter?.error?.localizedDescription))")
                            }
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                        self.pregress += pregressPerImg
                        i += 1
                    }
                    else {
                        print("Error: Adaptor is not ready")
                        Thread.sleep(forTimeInterval: 0.1)
                        i -= 1
                    }
                }
                
                writerInput.markAsFinished()
                
                self.pregress = 0.9
                self.videoWriter?.finishWriting(completionHandler: {() -> Void in
                    print("Finished writing")
                    self.videoWriter = nil
                    DispatchQueue.main.async(execute: {
                        self.pregress = 1.0
                        completion(true, nil)
                    })
                })
            }
        })
    }
    
    
    //MARK:- Private Methods
    //MARK:-
    fileprivate func sendProgress(pregress: CGFloat) {
        DispatchQueue.main.async(execute: {
            if let handler = self.progressHandler {
                handler(pregress)
            }
        })
    }
    
    //creating pixel buffer for the passed cgImage
    private func pixelBufferFromCGImage(image: CGImage, size: CGSize) -> CVPixelBuffer? {
        let attributes : [NSObject:AnyObject] = [
            kCVPixelBufferCGImageCompatibilityKey : true as AnyObject,
            kCVPixelBufferCGBitmapContextCompatibilityKey : true as AnyObject
        ]
        
        var pxbuffer: CVPixelBuffer? = nil
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, (attributes as CFDictionary), &pxbuffer)
    
        CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(pxbuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        if let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            
            context.concatenate(CGAffineTransform(rotationAngle: 0))
            context.draw(image, in: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
            CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
            return pxbuffer
        }
        else {
            return nil
        }
    }
    
    
    //converts tha gif Data in to the images array
    private func loadGIFData(data: Data, resize size: CGSize, repeatCount: Int) -> [String : AnyObject] {

        var frames = [AnyObject]() /* capacity: imgSrcCount */
        var animationTime: CGFloat = 0.0
        
        if let src = CGImageSourceCreateWithData((data as CFData), nil) {
            let imgSrcCount = CGImageSourceGetCount(src)
            //looping for the images present in gifdata
            for i in 0..<imgSrcCount {
                if let img = CGImageSourceCreateImageAtIndex(src, i, nil) {
                    if let properties = (CGImageSourceCopyPropertiesAtIndex(src, i, nil)) as? [String : AnyObject] {
                        if let frameProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String : AnyObject] {
                            
                            if let delayTime = frameProperties[(kCGImagePropertyGIFUnclampedDelayTime as String)] as? CGFloat {
                                
                                animationTime += delayTime
                                
                                if size.width != 0.0 && size.height != 0.0 {
                                    UIGraphicsBeginImageContext(size)
                                    var width: CGFloat = CGFloat(img.width)
                                    var height: CGFloat = CGFloat(img.height)
                                    var x: CGFloat = 0.0
                                    var y: CGFloat = 0.0
                                    if height > width {
                                        let padding: CGFloat = size.height / height
                                        height = height * padding
                                        width = width * padding
                                        x = (size.width / 2) - (width / 2)
                                        y = 0.0
                                    }
                                    else if width > height {
                                        let padding: CGFloat = size.width / width
                                        height = height * padding
                                        width = width * padding
                                        x = 0.0
                                        y = (size.height / 2) - (height / 2)
                                    }
                                    else {
                                        width = size.width
                                        height = size.height
                                    }
                                    
                                    
                                    UIImage(cgImage: img).draw(in: CGRect(x: x, y: y, width: width, height: height), blendMode: CGBlendMode.normal, alpha: 1.0)
                                    frames.append(UIGraphicsGetImageFromCurrentImageContext()!)
                                    UIGraphicsEndImageContext()
                                }
                                else {
                                    frames.append(UIImage(cgImage: img))
                                }
                            }
                        }
                    }
                }
            }
        }
        
        //repeating the images till repeat count
        let framesCopy = frames
        for _ in 1..<repeatCount {
            frames += framesCopy
        }
        return ["animationTime": Int(animationTime) * repeatCount as AnyObject, "frames": frames as AnyObject]
    }
}


//MARK:- URLSession Delegate Methods
//MARK:-
extension PKGIFConvertor: URLSessionDelegate, URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Swift.Void) {
    
        //here you can get full lenth of your content
        self.expectedContentLength = Int(response.expectedContentLength)
        print(self.expectedContentLength)
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        
        self.buffer.append(data)
        
        let percentageDownloaded = Float(buffer.length) / Float(self.expectedContentLength)
        
        self.pregress = CGFloat(percentageDownloaded / 2.0)
        print("Downloaded: \(percentageDownloaded)")
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        
        self.pregress = CGFloat(1.0/2.0)
        self.convertGIFToVideo(gif: self.buffer as Data, size: AppDefaultConstant.videoSize, output: self.videoPath, completion: { (success, error) in
            
            if let completion = self.complitionHandler {
                if success {
                    self.pregress = CGFloat(1.0)
                    completion(self.videoPath, nil)
                }
                else {
                    completion(nil, "Not able to convert gif")
                }
            }
        })
    }
}
