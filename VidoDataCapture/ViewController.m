//
//  ViewController.m
//  VidoDataCapture
//
//  Created by liqiang on 2023/4/23.
//
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "ViewController.h"
#import "TestView.h"
@interface ViewController ()<AVCaptureAudioDataOutputSampleBufferDelegate,AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic,strong)AVCaptureDeviceInput * frontCamera;
@property(nonatomic,strong)AVCaptureDeviceInput * backCamera;
@property(nonatomic,strong)AVCaptureDeviceInput * videoInputDevice;
@property(nonatomic,strong)AVCaptureDeviceInput * audioInputDevice;

@property(nonatomic,strong)AVCaptureVideoDataOutput * videoDataOutput;
@property(nonatomic,strong)AVCaptureAudioDataOutput * audioDataOutput;

@property(nonatomic,strong)AVCaptureSession * captrueSession;

@property(nonatomic,strong)AVCaptureVideoPreviewLayer * previewLayer;

@property (assign, nonatomic) VTCompressionSessionRef compressionSessionRef;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
//    [self inInit];
    TestView * view = [[TestView alloc] initWithFrame:CGRectMake(50, 50, 100, 100)];
    view.backgroundColor = [UIColor redColor];
    [self.view addSubview:view];
    
    // Do any additional setup after loading the view.
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    
    
}
- (void)inInit {
    [self createCaptureDevice];
    [self createOutput];
    [self createCaptureSession];
    [self createPreviewLayer];
    [self updateFps:20];
    
  
    
}
- (void)createEncoder {
    
    OSStatus status = VTCompressionSessionCreate(NULL, 180, 320, kCMVideoCodecType_H264, NULL, NULL, NULL, encodeOutPutDataCallback, (__bridge void*)self, &_compressionSessionRef);
    if(status != noErr) {
        NSLog(@"VEVideoEncoder::VTCompressionSessionCreate:failed status:%d", (int)status);
        return;
    }
    if(self.compressionSessionRef == NULL){
        NSLog(@"VEVideoEncoder::调用顺序错误");
        return;
    }
    //设置码率 平均码率
    if(![self adjustBitRate:512*1024]) {
        return;
    }
    
    // ProfileLevel，h264的协议等级，不同的清晰度使用不同的ProfileLevel。
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_3_1);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_ProfileLevel failed status:%d", (int)status);
        return;
    }
    //设置实时编码输出(避免延迟)
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_RealTime failed status:%d", (int)status);
        return;
    }
    
    //是否产生B帧
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_AllowFrameReordering failed status:%d", (int)status);
        return;
    }
    
    //I帧产生时间间隔
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(15*240));
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_MaxKeyFrameInterval failed status:%d", (int)status);
        return;
    }
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, (__bridge CFTypeRef)@(240));
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration failed status:%d", (int)status);
        return ;
    }
    
    status = VTCompressionSessionPrepareToEncodeFrames(_compressionSessionRef);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionPrepareToEncodeFrames failed status:%d", (int)status);
        return;
    }
    
    
}

/// 开始编码
- (BOOL)startVideoEncode {
    
    if(NULL == self.compressionSessionRef){
        NSLog(@"VEVideoEncoder::调用顺序错误");
        return NO;
    }
    OSStatus status = VTCompressionSessionPrepareToEncodeFrames(_compressionSessionRef);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionPrepareToEncodeFrames failed status:%d", (int)status);
        return NO;
    }
    
    return YES;
}
- (BOOL)stopVideoEncode {
    if(NULL == self.compressionSessionRef){
        return NO;
    }
    OSStatus status = VTCompressionSessionCompleteFrames(_compressionSessionRef, kCMTimeInvalid);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionCompleteFrames failed! status:%d", (int)status);
        return NO;
    }
    return YES;
}
void encodeOutPutDataCallback(void * CM_NULLABLE outputCallbackRefCon,void * CM_NULLABLE soureFrmeRefCon,OSStatus status,VTEncodeInfoFlags infoFlags,CM_NULLABLE CMSampleBufferRef sampleBuffer) {
    
}
- (BOOL)adjustBitRate:(NSInteger)bitRate {
    if (bitRate <= 0)
    {
        NSLog(@"VEVideoEncoder::adjustBitRate failed! bitRate <= 0");
        return NO;
    }
    OSStatus status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFTypeRef)@(bitRate));
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_AverageBitRate failed status:%d", (int)status);
        return NO;
    }
    
    int64_t dataLimitBytesPerSecondValue = bitRate * 1.5/8;
    CFNumberRef bytePerSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &dataLimitBytesPerSecondValue);
    int64_t oneSecondValue = 1;
    CFNumberRef onSecond = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &oneSecondValue);
    const void* nums[2] = {bytePerSecond,onSecond};
    CFArrayRef dataRateLimits = CFArrayCreate(NULL, nums, 2, &kCFTypeArrayCallBacks);
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_DataRateLimits, dataRateLimits);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_DataRateLimits failed status:%d", (int)status);
        return NO;
    }
    
    return YES;
    
}
//修改fps
-(void) updateFps:(NSInteger) fps{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    
    for (AVCaptureDevice *vDevice in videoDevices) {
        float maxRate = [(AVFrameRateRange *)[vDevice.activeFormat.videoSupportedFrameRateRanges objectAtIndex:0] maxFrameRate];
        if (maxRate >= fps) {
            if ([vDevice lockForConfiguration:NULL]) {
                vDevice.activeVideoMinFrameDuration = CMTimeMake(10, (int)(fps * 10));
                vDevice.activeVideoMaxFrameDuration = vDevice.activeVideoMinFrameDuration;
                [vDevice unlockForConfiguration];
            }
        }
    }
}
- (void)createCaptureDevice {
    NSArray * videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    self.frontCamera = [AVCaptureDeviceInput deviceInputWithDevice:videoDevices.firstObject error:nil];
    self.backCamera = [AVCaptureDeviceInput deviceInputWithDevice:videoDevices.lastObject error:nil];
    
    AVCaptureDevice * audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    self.audioInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    self.videoInputDevice = self.frontCamera;
}
- (void)createCaptureSession {
    self.captrueSession = [[AVCaptureSession alloc] init];
    [self.captrueSession beginConfiguration];
    
    if([self.captrueSession canAddInput:self.videoInputDevice]){
        [self.captrueSession addInput:self.videoInputDevice];
    }
    
    if([self.captrueSession canAddInput:self.audioInputDevice]) {
        [self.captrueSession addInput:self.audioInputDevice];
    }
    
    if([self.captrueSession canAddOutput:self.videoDataOutput]) {
        [self.captrueSession addOutput:self.videoDataOutput];
    }
    
    if([self.captrueSession canAddOutput:self.audioDataOutput]) {
        [self.captrueSession addOutput:self.audioDataOutput];
    }
    
    [self.captrueSession commitConfiguration];
    [self.captrueSession startRunning];
}
- (void)createPreviewLayer{
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captrueSession];
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer addSublayer:self.previewLayer];
}
- (void)createOutput {
    dispatch_queue_t captureQueue = dispatch_queue_create("com.VidoDataCapture.lqqjob.VidoDataCapture", DISPATCH_QUEUE_SERIAL);
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.videoDataOutput setSampleBufferDelegate:self queue:captureQueue];
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    [self.videoDataOutput setVideoSettings:@{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }];
    
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioDataOutput setSampleBufferDelegate:self queue:captureQueue];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
  
    
}

@end
