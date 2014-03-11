//
//  VWWCaptureFromVideoViewController.m
//  ColorBlind2
//
//  Created by Zakk Hoyt on 12/2/13.
//  Copyright (c) 2013 Zakk Hoyt. All rights reserved.
//
// Some good stuff about augmented reality here: http://cmgresearch.blogspot.com/2010/10/augmented-reality-on-iphone-with-ios40.html
// A forum post about AVAssetWriter: http://stackoverflow.com/questions/4149963/this-code-to-write-videoaudio-through-avassetwriter-and-avassetwriterinputs-is
// A forum post about orientation: http://stackoverflow.com/questions/3561738/why-avcapturesession-output-a-wrong-orientation

#import "VWWCaptureVideoViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "VWWDataLogController.h"
#import "NSTimer+Blocks.h"
#import "VWWEditVideoTableViewController.h"
#import "VWWFileController.h"

static NSString *VWWSegueRecordToEdit = @"VWWSegueRecordToEdit";

@interface VWWCaptureVideoViewController () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, VWWDataLogControllerDelegate>
// IB
@property (weak, nonatomic) IBOutlet UIView *cameraView;
@property (weak, nonatomic) IBOutlet UIButton *startButton;
@property (weak, nonatomic) IBOutlet UISwitch *overlaySwitch;
@property (weak, nonatomic) IBOutlet UILabel *overlayLabel;

// iVars
@property dispatch_queue_t avqueue;
@property (nonatomic) BOOL isRecording;
@property (nonatomic, strong) VWWDataLogController *dataLogController;
// iVars AVFoundation
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *videoPreviewLayer;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVAssetWriter *videoWriter;
@property (nonatomic, strong) AVAssetWriterInput* writerInput;
//@property (nonatomic, strong) AVCaptureConnection *connection;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *adaptor;
@end

@implementation VWWCaptureVideoViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.avqueue = dispatch_queue_create("com.vaporwarewolf.avfoundation", NULL);
    [self setupCaptureSession];
    [self setupAssetWriter];
}


-(void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = NO;
    self.overlayLabel.text = @"";
    self.overlaySwitch.on = [VWWUserDefaults overlayDataOnVideo];
    self.overlayLabel.hidden = ![VWWUserDefaults overlayDataOnVideo];
    
    self.dataLogController = [VWWDataLogController sharedInstance];
    self.dataLogController.delegate = self;
    [self.dataLogController start];
    
    
    

    [NSTimer scheduledTimerWithTimeInterval:0.25 block:^{
        [self.dataLogController calibrate];
    } repeats:NO];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//-(BOOL)prefersStatusBarHidden{
//    return YES;
//}


-(void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender{
    if([segue.identifier isEqualToString:VWWSegueRecordToEdit]){
        VWWEditVideoTableViewController *vc = segue.destinationViewController;
        vc.videoURL = sender;
    }
}
#pragma mark IBActions


- (IBAction)calibrateButtonTouchUpInside:(id)sender {
    [self.dataLogController calibrate];
}

- (IBAction)startButtonTouchUpInside:(id)sender {
    if(self.isRecording == YES){
        [self stopRecording];
    } else {
        [self startRecording];
    }
    
    self.isRecording = !self.isRecording;
}



- (IBAction)overlaySwitchValueChanged:(UISwitch*)sender {
    [VWWUserDefaults setOverlayDataOnVideo:sender.on];
    self.overlayLabel.hidden = !sender.on;
}

#pragma mark Private methods


-(void)startRecording{
    
    [self.startButton setTitle:@"Stop" forState:UIControlStateNormal];

    
    NSString *myPathDocs =  [[VWWFileController pathForDocumentsDirectory] stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"FinalVideo-%d.mov",arc4random() % 1000]];
    NSURL *url = [NSURL fileURLWithPath:myPathDocs];
    
    [self.movieFileOutput startRecordingToOutputFileURL:url recordingDelegate:self];
    [self startAssetWriter];
    
}

-(void)stopRecording{
    [self.startButton setTitle:@"Start" forState:UIControlStateNormal];
    [self.movieFileOutput stopRecording];
    [self stopAssetWriter];
    // VC is presented from recording delegate
}

-(BOOL)isCameraAvailable{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    BOOL cameraFound = NO;
    for (AVCaptureDevice *device in videoDevices) {
        if (device.position == AVCaptureDevicePositionBack){
            cameraFound = YES;
        }
    }
    return cameraFound;
}


// Forum on AVAssetWriter: http://stackoverflow.com/questions/3741323/how-do-i-export-uiimage-array-as-a-movie/3742212#3742212
// An example post for creating from an array of images: http://www.developers-life.com/create-movie-from-array-of-images.html
-(void)setupAssetWriter{
    NSError *error = nil;
    NSString *myPathDocs =  [[VWWFileController pathForDocumentsDirectory] stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"AssetWriter-%d.mov",arc4random() % 1000]];
    NSURL *url = [NSURL fileURLWithPath:myPathDocs];

    self.videoWriter = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
    NSParameterAssert(self.videoWriter);
    
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:640], AVVideoWidthKey,
                                   [NSNumber numberWithInt:480], AVVideoHeightKey,
                                   nil];
    
    self.writerInput = [AVAssetWriterInput
                                        assetWriterInputWithMediaType:AVMediaTypeVideo
                                        outputSettings:videoSettings];
    
    
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    [attributes setObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [attributes setObject:[NSNumber numberWithUnsignedInt:640] forKey:(NSString*)kCVPixelBufferWidthKey];
    [attributes setObject:[NSNumber numberWithUnsignedInt:480] forKey:(NSString*)kCVPixelBufferHeightKey];
    
    self.adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.writerInput
                                                                                    sourcePixelBufferAttributes:attributes];
    
    // fixes all errors
    self.writerInput.expectsMediaDataInRealTime = YES;
    
    NSParameterAssert(self.writerInput);
    NSParameterAssert([self.videoWriter canAddInput:self.writerInput]);
    [self.videoWriter addInput:self.writerInput];
    
    
    
}


-(void)startAssetWriter{
    [self.videoWriter startWriting];
    [self.videoWriter startSessionAtSourceTime:kCMTimeZero];
    
}

-(void)stopAssetWriter{
    [self.writerInput markAsFinished];
    [self.videoWriter endSessionAtSourceTime:CMTimeMake(1, 100)];
    [self.videoWriter finishWritingWithCompletionHandler:^{
        VWW_LOG_DEBUG(@"Finished writing AVAssetWriter");
    }];
}

-(void)setupCaptureSession{
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetMedium;
    
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error;
    [self.device lockForConfiguration:&error];

    if(error){
        VWW_LOG_WARNING(@"Cannot lock device to set framerate");
    } else {
        self.device.activeVideoMinFrameDuration = CMTimeMake(1, 5);
        self.device.activeVideoMaxFrameDuration  = CMTimeMake(1, 5);
    }
    error = nil;

    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:&error];
    
    if (!self.input) {
        VWW_LOG_WARNING(@"Couldnt' create AV video capture device");
    }
    [self.session addInput:self.input];
    
    self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    
    if([self.session canAddOutput:self.movieFileOutput]){
        [self.session addOutput:self.movieFileOutput];
    } else {
        VWW_LOG_DEBUG(@"Cannot add file output");
    }
    
    
    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    NSMutableDictionary *cameraVideoSettings = [[NSMutableDictionary alloc] init];
    NSString *key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber *value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA]; //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];
    [cameraVideoSettings setValue:value forKey:key];
    [self.videoOutput setVideoSettings:cameraVideoSettings];
    [self.videoOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.videoOutput setSampleBufferDelegate:self queue:self.avqueue];
    
    
    // set the videoOrientation based on the device orientation to
    // ensure the pic is right side up for all orientations
    AVCaptureVideoOrientation videoOrientation;
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationLandscapeLeft:
            // Not clear why but the landscape orientations are reversed
            // if I use AVCaptureVideoOrientationLandscapeLeft here the pic ends up upside down
            videoOrientation = AVCaptureVideoOrientationLandscapeRight;
            break;
        case UIDeviceOrientationLandscapeRight:
            // Not clear why but the landscape orientations are reversed
            // if I use AVCaptureVideoOrientationLandscapeRight here the pic ends up upside down
            videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        default:
            videoOrientation = AVCaptureVideoOrientationPortrait;
            break;
    }
    
    // set portrait orientation

    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if([conn isVideoOrientationSupported]){
        [conn setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
    } else {
        VWW_LOG_WARNING(@"video orientaiton not supported");
    }


    
    
    
    if([self.session canAddOutput:self.videoOutput]){
        [self.session addOutput:self.videoOutput];
    }
    else {
        NSLog(@"Could not add videoOutput");
    }
    
    


    
    
    
    
    self.videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.session];
    UIView *view = self.cameraView;
    CALayer *viewLayer = [view layer];
    
    self.videoPreviewLayer.frame = view.bounds;
    [viewLayer addSublayer:self.videoPreviewLayer];
    
    
    
    
//    AVCaptureConnection *connection;
//    self.videoOutput.videoSettings
////    self.session.videoOrientation = videoOrientation;
//    videoConnection.videoOrientation = videoOrientation;
    
    [self.session startRunning];

}


- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(image),
                        CGImageGetHeight(image), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef) options,
                        &pxbuffer);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(image),
                                                 CGImageGetHeight(image), 8, 4*CGImageGetWidth(image), rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    
    CGAffineTransform flipVertical = CGAffineTransformMake(
                                                           1, 0, 0, -1, 0, CGImageGetHeight(image)
                                                           );
    CGContextConcatCTM(context, flipVertical);
    
    
    
    CGAffineTransform flipHorizontal = CGAffineTransformMake(
                                                             -1.0, 0.0, 0.0, 1.0, CGImageGetWidth(image), 0.0
                                                             );
    
    CGContextConcatCTM(context, flipHorizontal);
    
    
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}


#pragma mark AVCaptureVideoDataOutputSampleBufferDelegate

// For image resizing, see the following links:
// http://stackoverflow.com/questions/4712329/how-to-resize-the-image-programatically-in-objective-c-in-iphone
// http://stackoverflow.com/questions/6052188/high-quality-scaling-of-uiimage

-(void)captureOutput :(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection{
    
    
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
//    // Create an image object from the Quartz image
//    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    
    // Or you can use AVAssetWriterInputPixelBufferAdaptor.
    // That lets you feed the writer input data from a CVPixelBuffer
    // that’s quite easy to create from a CGImage.
//    if([self.writerInput appendSampleBuffer:sampleBuffer] == NO){
//        VWW_LOG_WARNING(@"could not append sample buffer");
//    }
    static int i = 0;
    int fps = 30;
    CMTime frameTime = CMTimeMake(1, fps);
    CMTime lastTime=CMTimeMake(i, fps);
    CMTime presentTime=CMTimeAdd(lastTime, frameTime);
    
    BOOL result = [self.adaptor appendPixelBuffer:[self pixelBufferFromCGImage:quartzImage] withPresentationTime:presentTime];
    
    if (result == NO) //failes on 3GS, but works on iphone 4
    {
        NSLog(@"failed to append buffer");
        NSLog(@"The error is %@", [self.videoWriter error]);
    }
    i++;

    
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    static bool hasRunOnce = NO;
    if(!hasRunOnce){
        hasRunOnce = YES;
        NSLog(@"Camera is outputting frames at %dx%d", (int)width, (int)height);
//        NSLog(@"We will be examinign pixel in row %d column %d", (int)(halfWidth * height), (int)halfHeight);
    }
    
    
//    dispatch_sync(dispatch_get_main_queue(), ^{
//    });
}

#pragma mark AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
      fromConnections:(NSArray *)connections{
    VWW_LOG_DEBUG(@"Started recording to file at :%@", fileURL);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error{
    if(error){
        VWW_LOG_ERROR(@"Could not record file %@\n%@", outputFileURL, error.description);
    } else {
        VWW_LOG_DEBUG(@"Finished recording to file at :%@", outputFileURL);
        [self performSegueWithIdentifier:VWWSegueRecordToEdit sender:outputFileURL];
    }
    
}


#pragma mark VWWDataLogControllerDelegate
-(void)dataLogController:(VWWDataLogController*)sender didLogDataPoint:(NSDictionary*)dataPoint{
}

-(void)dataLogController:(VWWDataLogController *)sender didUpdateLogString:(NSString*)logString{
    self.overlayLabel.text = logString;
}



@end
