/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <AudioToolbox/AudioToolbox.h>

//------------------------------------------------------------------------------
// use the all-in-one version of zxing that we built
//------------------------------------------------------------------------------
//#import "zxing-all-in-one.h"
#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
// Adds a shutter button to the UI, and changes the scan from continuous to
// only performing a scan when you click the shutter button.  For testing.
//------------------------------------------------------------------------------
#define USE_SHUTTER 0

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)scan:(CDVInvokedUrlCommand*)command;
- (void)encode:(CDVInvokedUrlCommand*)command;
- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback;
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped manual:(BOOL)manual callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureMetadataOutputObjectsDelegate /*AVCaptureVideoDataOutputSampleBufferDelegate*/> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSString*                   alternateXib;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   formats;
@property (nonatomic)         BOOL                        is1D;
@property (nonatomic)         BOOL                        is2D;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        isFrontCamera;
@property (nonatomic)         BOOL                        isShowFlipCameraButton;
@property (nonatomic)         BOOL                        isFlipped;


- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController alterateOverlayXib:(NSString *)alternateXib;
- (void)scanBarcode;
- (void)barcodeInputed:(NSString *)barcode;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (void)openDialog;
- (NSString*)setUpCaptureSession;
//- (void)captureOutput:(AVCaptureOutput*)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection*)connection;
//- (NSString*)formatStringFrom:(zxing::BarcodeFormat)format;
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer;
//- (zxing::Ref<zxing::LuminanceSource>) getLuminanceSourceFromSample:(CMSampleBufferRef)sampleBuffer imageBytes:(uint8_t**)ptr;
//- (UIImage*) getImageFromLuminanceSource:(zxing::LuminanceSource*)luminanceSource;
//- (void)dumpImage:(UIImage*)image;
@end

//------------------------------------------------------------------------------
// Qr encoder processor
//------------------------------------------------------------------------------
@interface CDVqrProcessor: NSObject
@property (nonatomic, retain) CDVBarcodeScanner*          plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) NSString*                   stringToEncode;
@property                     NSInteger                   size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode;

@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
@property (nonatomic, retain) CDVbcsProcessor*  processor;
@property (nonatomic, retain) NSString*        alternateXib;
@property (nonatomic)         BOOL             shutterPressed;
@property (nonatomic, retain) IBOutlet UITextField *barcodeInput;
@property (nonatomic, retain) IBOutlet UIView *overlayView;
@property (nonatomic, retain) IBOutlet UIButton *sendButton;
@property (nonatomic) BOOL keyboardIsShowing;
// unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
@property (nonatomic, unsafe_unretained) id orientationDelegate;

- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib;

@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;
    
    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }
    
    return result;
}

//--------------------------------------------------------------------------
- (void)scan:(CDVInvokedUrlCommand*)command {
    CDVbcsProcessor* processor;
    NSString*       callback;
    NSString*       capabilityError;
    
    callback = command.callbackId;
    
    NSDictionary* options = command.arguments.count == 0 ? [NSNull null] : [command.arguments objectAtIndex:0];
    
    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }
    BOOL preferFrontCamera = [options[@"preferFrontCamera"] boolValue];
    BOOL showFlipCameraButton = [options[@"showFlipCameraButton"] boolValue];
    // We allow the user to define an alternate xib file for loading the overlay.
//    NSString *overlayXib = [options objectForKey:@"overlayXib"];
    NSString *overlayXib = @"scannerOverlay";
    
    capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback:callback];
        return;
    }
    
    processor = [[CDVbcsProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 parentViewController:self.viewController
                 alterateOverlayXib:overlayXib
                 ];
    // queue [processor scanBarcode] to run on the event loop
    
    if (preferFrontCamera) {
        processor.isFrontCamera = true;
    }
    
    if (showFlipCameraButton) {
        processor.isShowFlipCameraButton = true;
    }
    
    processor.formats = options[@"formats"];
    
    [processor performSelector:@selector(scanBarcode) withObject:nil afterDelay:0];
}

//--------------------------------------------------------------------------
- (void)encode:(CDVInvokedUrlCommand*)command {
    if([command.arguments count] < 1)
        [self returnError:@"Too few arguments!" callback:command.callbackId];
    
    CDVqrProcessor* processor;
    NSString*       callback;
    callback = command.callbackId;
    
    processor = [[CDVqrProcessor alloc]
                 initWithPlugin:self
                 callback:callback
                 stringToEncode: command.arguments[0][@"data"]
                 ];
    
    [processor retain];
    [processor retain];
    [processor retain];
    // queue [processor generateImage] to run on the event loop
    [processor performSelector:@selector(generateImage) withObject:nil afterDelay:0];
}

- (void)returnImage:(NSString*)filePath format:(NSString*)format callback:(NSString*)callback{
    NSMutableDictionary* resultDict = [[[NSMutableDictionary alloc] init] autorelease];
    [resultDict setObject:format forKey:@"format"];
    [resultDict setObject:filePath forKey:@"file"];
    
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_OK
                               messageAsDictionary:resultDict
                               ];
    
    [[self commandDelegate] sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(NSString*)format cancelled:(BOOL)cancelled flipped:(BOOL)flipped manual:(BOOL)manual callback:(NSString*)callback{
    NSNumber* cancelledNumber = [NSNumber numberWithInt:(cancelled?1:0)];
    
    NSMutableDictionary* resultDict = [[NSMutableDictionary alloc] init];
    [resultDict setObject:scannedText     forKey:@"text"];
    [resultDict setObject:format          forKey:@"format"];
    [resultDict setObject:cancelledNumber forKey:@"cancelled"];
    [resultDict setObject:[NSNumber numberWithBool:manual] forKey:@"manual"];
    
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                            messageAsDictionary:resultDict];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    CDVPluginResult* result = [CDVPluginResult
                               resultWithStatus: CDVCommandStatus_ERROR
                               messageAsString: message
                               ];
    
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize alternateXib         = _alternateXib;
@synthesize is1D                 = _is1D;
@synthesize is2D                 = _is2D;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

SystemSoundID _soundFileObject;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController
  alterateOverlayXib:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;
    self.alternateXib         = alternateXib;
    
    self.is1D      = YES;
    self.is2D      = YES;
    self.capturing = NO;
    self.results = [NSMutableArray new];
    
    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.alternateXib = nil;
    self.results = nil;
    
    self.capturing = NO;
    
    AudioServicesRemoveSystemSoundCompletion(_soundFileObject);
    AudioServicesDisposeSystemSoundID(_soundFileObject);
    
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)scanBarcode {
    
    //    self.captureSession = nil;
    //    self.previewLayer = nil;
    NSString* errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        [self barcodeScanFailed:errorMessage];
        return;
    }
    
    self.viewController = [[CDVbcsViewController alloc] initWithProcessor: self alternateOverlay:self.alternateXib];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;
    
    // delayed [self openDialog];
    [self performSelector:@selector(openDialog) withObject:nil afterDelay:1];
}

//--------------------------------------------------------------------------
- (void)openDialog {
    [self.parentViewController presentViewController:self.viewController
                                            animated:YES
                                          completion:nil];
}

//--------------------------------------------------------------------------
- (void)barcodeScanDone {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated: YES completion:nil];
    
    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(NSString*)format {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self barcodeScanDone];
        AudioServicesPlaySystemSound(_soundFileObject);
        [self.plugin returnSuccess:text format:format cancelled:FALSE flipped:FALSE  manual:false callback:self.callback];
    });
}

- (void)barcodeInputed:(NSString *)barcode {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self barcodeScanDone];
        [self.plugin returnSuccess:barcode format:barcode cancelled:FALSE flipped:FALSE manual:true callback:self.callback];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    [self barcodeScanDone];
    [self.plugin returnError:message callback:self.callback];
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone];
    [self.plugin returnSuccess:@"" format:@"" cancelled:TRUE flipped:self.isFlipped manual:false callback:self.callback];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}

- (void)flipCamera {
    self.isFlipped = YES;
    self.isFrontCamera = !self.isFrontCamera;
    [self barcodeScanDone];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
    [self performSelector:@selector(scanBarcode) withObject:nil afterDelay:0.1];
}

//--------------------------------------------------------------------------
- (NSString*)setUpCaptureSession {
    NSError* error = nil;
    
    AVCaptureSession* captureSession = [[AVCaptureSession alloc] init];
    self.captureSession = captureSession;
    
    AVCaptureDevice* __block device = nil;
    if (self.isFrontCamera) {
        
        NSArray* devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        [devices enumerateObjectsUsingBlock:^(AVCaptureDevice *obj, NSUInteger idx, BOOL *stop) {
            if (obj.position == AVCaptureDevicePositionFront) {
                device = obj;
            }
        }];
    } else {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        if (!device) return @"unable to obtain video capture device";
        
    }
    
    
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) return @"unable to obtain video capture device input";
    
    //    AVCaptureVideoDataOutput* output = [[AVCaptureVideoDataOutput alloc] init];
    //    if (!output) return @"unable to obtain video capture output";
    
    AVCaptureMetadataOutput* output = [[AVCaptureMetadataOutput alloc] init];
    if (!output) return @"unable to obtain metadata capture output";
    
    //    NSDictionary* videoOutputSettings = [NSDictionary
    //                                         dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
    //                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey
    //                                         ];
    //
    //    output.alwaysDiscardsLateVideoFrames = YES;
    //    output.videoSettings = videoOutputSettings;
    //
    //    [output setSampleBufferDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
    
    if ([captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    } else if ([captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    } else {
        return @"unable to preset high nor medium quality video capture";
    }
    
    if ([captureSession canAddInput:input]) {
        [captureSession addInput:input];
    }
    else {
        return @"unable to add video capture device input to session";
    }
    
    if ([captureSession canAddOutput:output]) {
        [captureSession addOutput:output];
        output.metadataObjectTypes = [output availableMetadataObjectTypes];
        [output setMetadataObjectsDelegate:self queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
    }
    else {
        return @"unable to add video capture output to session";
    }
    
    // setup capture preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    // run on next event loop pass [captureSession startRunning]
    [captureSession performSelector:@selector(startRunning) withObject:nil afterDelay:0];
    
    return nil;
}

//--------------------------------------------------------------------------
// this method gets sent the captured frames
//--------------------------------------------------------------------------
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    
    AVMetadataMachineReadableCodeObject *barCodeObject = nil;
    NSArray *barCodeTypes = @[AVMetadataObjectTypeUPCECode, AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode39Mod43Code,
                              AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeEAN8Code, AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeCode128Code,
                              AVMetadataObjectTypePDF417Code, AVMetadataObjectTypeQRCode, AVMetadataObjectTypeAztecCode];
    
    for (AVMetadataObject *metadata in metadataObjects) {
        for (NSString *type in barCodeTypes) {
            if ([metadata.type isEqualToString:type]) {
                barCodeObject = (AVMetadataMachineReadableCodeObject *)[_previewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject *)metadata];
                break;
            }
        }
        
        if (nil != barCodeObject) {
            [self barcodeScanSucceeded:[barCodeObject stringValue]
                                format:[self formatStringFrom:barCodeObject.type]];
            break;
        }
    }
}

- (NSString *)formatStringFrom:(NSString *)format {
    if (format == AVMetadataObjectTypeQRCode)      return @"QR_CODE";
    if (format == AVMetadataObjectTypeUPCECode)        return @"UPC_E";
    if (format == AVMetadataObjectTypeEAN8Code)        return @"EAN_8";
    if (format == AVMetadataObjectTypeEAN13Code)       return @"EAN_13";
    if (format == AVMetadataObjectTypeCode128Code)     return @"CODE_128";
    if (format == AVMetadataObjectTypeCode39Code)      return @"CODE_39";
    return @"???";
}

//--------------------------------------------------------------------------
// for debugging
//--------------------------------------------------------------------------
- (UIImage*)getImageFromSample:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width       = CVPixelBufferGetWidth(imageBuffer);
    size_t height      = CVPixelBufferGetHeight(imageBuffer);
    
    uint8_t* baseAddress    = (uint8_t*) CVPixelBufferGetBaseAddress(imageBuffer);
    int      length         = (int)(height * bytesPerRow);
    uint8_t* newBaseAddress = (uint8_t*) malloc(length);
    memcpy(newBaseAddress, baseAddress, length);
    baseAddress = newBaseAddress;
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
                                                 baseAddress,
                                                 width, height, 8, bytesPerRow,
                                                 colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst
                                                 );
    
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage*   image   = [[UIImage alloc] initWithCGImage:cgImage];
    
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cgImage);
    
    free(baseAddress);
    
    return image;
}

@end

//------------------------------------------------------------------------------
// qr encoder processor
//------------------------------------------------------------------------------
@implementation CDVqrProcessor
@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize stringToEncode       = _stringToEncode;
@synthesize size                 = _size;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback stringToEncode:(NSString*)stringToEncode{
    self = [super init];
    if (!self) return self;
    
    self.plugin          = plugin;
    self.callback        = callback;
    self.stringToEncode  = stringToEncode;
    self.size            = 300;
    
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.stringToEncode = nil;
    
    [super dealloc];
}
//--------------------------------------------------------------------------
- (void)generateImage{
    /* setup qr filter */
    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    
    /* set filter's input message
     * the encoding string has to be convert to a UTF-8 encoded NSData object */
    [filter setValue:[self.stringToEncode dataUsingEncoding:NSUTF8StringEncoding]
              forKey:@"inputMessage"];
    
    /* on ios >= 7.0  set low image error correction level */
    if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_7_0)
        [filter setValue:@"L" forKey:@"inputCorrectionLevel"];
    
    /* prepare cgImage */
    CIImage *outputImage = [filter outputImage];
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:outputImage
                                       fromRect:[outputImage extent]];
    
    /* returned qr code image */
    UIImage *qrImage = [UIImage imageWithCGImage:cgImage
                                           scale:1.
                                     orientation:UIImageOrientationUp];
    /* resize generated image */
    CGFloat width = _size;
    CGFloat height = _size;
    
    UIGraphicsBeginImageContext(CGSizeMake(width, height));
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    [qrImage drawInRect:CGRectMake(0, 0, width, height)];
    qrImage = UIGraphicsGetImageFromCurrentImageContext();
    
    /* clean up */
    UIGraphicsEndImageContext();
    CGImageRelease(cgImage);
    
    /* save image to file */
    NSString* filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmpqrcode.jpeg"];
    [UIImageJPEGRepresentation(qrImage, 1.0) writeToFile:filePath atomically:YES];
    
    /* return file path back to cordova */
    [self.plugin returnImage:filePath format:@"QR_CODE" callback: self.callback];
}
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize shutterPressed = _shutterPressed;
@synthesize alternateXib   = _alternateXib;
@synthesize overlayView    = _overlayView;

//--------------------------------------------------------------------------
- (id)initWithProcessor:(CDVbcsProcessor*)processor alternateOverlay:(NSString *)alternateXib {
    self = [super init];
    if (!self) return self;
    
    self.processor = processor;
    self.shutterPressed = NO;
    self.alternateXib = alternateXib;
    self.overlayView = nil;
    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.view = nil;
    self.processor = nil;
    self.shutterPressed = NO;
    self.alternateXib = nil;
    self.overlayView = nil;
    [super dealloc];
}

//--------------------------------------------------------------------------
- (void)loadView {
    [[NSBundle mainBundle] loadNibNamed:self.alternateXib owner:self options:NULL];
    CGSize overlaySize = self.overlayView.bounds.size;
    UIImage* reticleImage = [self buildReticleImage];
    UIView* reticleView = [[UIImageView alloc] initWithImage: reticleImage];
    CGFloat minAxis = MIN(overlaySize.height, overlaySize.width);
    CGRect rectArea = CGRectMake(0.5 * (overlaySize.width  - minAxis), 0.5 * (overlaySize.height - minAxis), minAxis, minAxis);
    [reticleView setFrame:rectArea];
    reticleView.opaque           = NO;
    reticleView.contentMode      = UIViewContentModeScaleAspectFit;
    reticleView.autoresizingMask = 0
    | UIViewAutoresizingFlexibleLeftMargin
    | UIViewAutoresizingFlexibleRightMargin
    | UIViewAutoresizingFlexibleTopMargin
    | UIViewAutoresizingFlexibleBottomMargin;
    [self.overlayView addSubview: reticleView];
    
    [self.overlayView.layer insertSublayer:self.processor.previewLayer
                                     below:[[self.overlayView.layer sublayers] objectAtIndex:0]];
    
    if ([self.barcodeInput respondsToSelector:@selector(setAttributedPlaceholder:)]) {
        self.barcodeInput.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"наприклад 001020300" attributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]}];
    }
    
    self.barcodeInput.layer.cornerRadius = 5;
    self.barcodeInput.layer.masksToBounds = YES;
    self.barcodeInput.layer.borderColor = [[UIColor whiteColor] CGColor];
    self.barcodeInput.layer.borderWidth = 1;
    
    [self.barcodeInput addTarget:self
                          action:@selector(barcodeChanged)
                forControlEvents:UIControlEventEditingChanged];
    
    UIView *paddingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, 20)];
    self.barcodeInput.leftView = paddingView;
    self.barcodeInput.leftViewMode = UITextFieldViewModeAlways;
}

//--------------------------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
}

//--------------------------------------------------------------------------
- (void)viewDidAppear:(BOOL)animated {
    [self startCapturing];
    
    [super viewDidAppear:animated];
    
    [self willAnimateRotationToInterfaceOrientation:[[UIDevice currentDevice] orientation]
                                           duration:0];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGSize keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y = -keyboardSize.height;
        self.view.frame = f;
    }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [UIView animateWithDuration:0.3 animations:^{
        CGRect f = self.view.frame;
        f.origin.y = 0.0f;
        self.view.frame = f;
    }];
}

//--------------------------------------------------------------------------
- (void)startCapturing {
    self.processor.capturing = YES;
}

//--------------------------------------------------------------------------
- (IBAction)cancelButtonPressed:(id)sender {
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (IBAction)sendBarcode {
    [self.processor performSelector:@selector(barcodeInputed:) withObject:self.barcodeInput.text afterDelay:0];
}

- (void)barcodeChanged {
    self.sendButton.enabled = self.barcodeInput.text.length;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    if ([self.barcodeInput isFirstResponder] && [touch view] != self.barcodeInput) {
        [self.barcodeInput resignFirstResponder];
    }
    
    [super touchesBegan:touches withEvent:event];
}

//--------------------------------------------------------------------------

#define RETICLE_SIZE    500.0f
#define RETICLE_WIDTH    10.0f
#define RETICLE_OFFSET   60.0f
#define RETICLE_ALPHA     0.4f

//-------------------------------------------------------------------------
// builds the green box and red line
//-------------------------------------------------------------------------
- (UIImage*)buildReticleImage {
    UIImage* result;
    UIGraphicsBeginImageContext(CGSizeMake(RETICLE_SIZE, RETICLE_SIZE));
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    if (self.processor.is1D) {
        UIColor* color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextBeginPath(context);
        CGFloat lineOffset = RETICLE_OFFSET+(0.5*RETICLE_WIDTH);
        CGContextMoveToPoint(context, lineOffset, RETICLE_SIZE/2);
        CGContextAddLineToPoint(context, RETICLE_SIZE-lineOffset, 0.5*RETICLE_SIZE);
        CGContextStrokePath(context);
    }
    
    if (self.processor.is2D) {
        UIColor* color = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:RETICLE_ALPHA];
        CGContextSetStrokeColorWithColor(context, color.CGColor);
        CGContextSetLineWidth(context, RETICLE_WIDTH);
        CGContextStrokeRect(context,
                            CGRectMake(
                                       RETICLE_OFFSET,
                                       RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET,
                                       RETICLE_SIZE-2*RETICLE_OFFSET
                                       )
                            );
    }
    
    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark CDVBarcodeScannerOrientationDelegate

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[UIApplication sharedApplication] statusBarOrientation];
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector:@selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation:interfaceOrientation];
    }
    
    return YES;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration {
    [UIView setAnimationsEnabled:NO];
    AVCaptureVideoPreviewLayer *previewLayer = self.processor.previewLayer;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    CGSize size = self.overlayView.bounds.size;
    previewLayer.frame = CGRectMake(0, 0, size.width, size.height);
    
    if (orientation == UIInterfaceOrientationLandscapeLeft) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeLeft];
    } else if (orientation == UIInterfaceOrientationLandscapeRight) {
        [previewLayer setOrientation:AVCaptureVideoOrientationLandscapeRight];
    } else if (orientation == UIInterfaceOrientationPortrait) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortrait];
    } else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        [previewLayer setOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
    }
    
    [UIView setAnimationsEnabled:YES];
}

@end