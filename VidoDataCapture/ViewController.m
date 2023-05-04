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


@property (strong, nonatomic) NSFileHandle * fileHandle;

@end


static ViewController * objc;

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    objc = self;
    NSString * fileName = [NSString stringWithFormat:@"%ld",[[NSDate date] timeIntervalSince1970]];
    
     NSString *homePath  = NSHomeDirectory();
    NSString *sourcePath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Documents/%@.h264",fileName]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![[NSFileManager defaultManager] createFileAtPath:sourcePath contents:nil attributes:nil]) {
        
    }
     _fileHandle= [NSFileHandle fileHandleForWritingAtPath:sourcePath];
//     [self.fileHandle writeData:stringData];
//     [self.fileHandle closeFile];
    
    
    [self inInit];
//    TestView * view = [[TestView alloc] initWithFrame:CGRectMake(50, 50, 100, 100)];
//    view.backgroundColor = [UIColor redColor];
//    [self.view addSubview:view];
    
    // Do any additional setup after loading the view.
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.captrueSession stopRunning];
    [self stopVideoEncode];
    [self.fileHandle closeFile];
    
}
- (void)inInit {
    [self createCaptureDevice];
    [self createOutput];
    [self createCaptureSession];
    [self createPreviewLayer];
    [self updateFps:20];
    
  
    [self createEncoder];
//    [self startVideoEncode];
    
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
    
    //每个几个帧创建一个关键帧 100 表示每隔99帧创建一个关键帧
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
    if(noErr != status || nil == sampleBuffer) {
        NSLog(@"VEVideoEncoder::encodeOutputCallback Error : %d!", (int)status);
        return;
    }
    if(nil == outputCallbackRefCon) {
        NSLog(@"outputCallbackRefCon = nil");
        return;
    }
    if(!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"!CMSampleBufferDataIsReady(sampleBuffer)");
        return;
    }
    ViewController *encoder = (__bridge ViewController *)outputCallbackRefCon;

    const char header[] = "\x00\x00\x00\x01";
    size_t headerLen = sizeof(header) - 1;
    NSData * headerData = [NSData dataWithBytes:header length:headerLen];
    bool isKeyFrame = !CFDictionaryContainsKey(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES), 0), (const void*)kCMSampleAttachmentKey_NotSync);
    if(isKeyFrame) {
        NSLog(@"VEVideoEncoder::编码了一个关键帧");
        CMFormatDescriptionRef formateDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        size_t sParameterSetSize,sParameterSetCount;
        const uint8_t * sParameterSet;
        OSStatus spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formateDescriptionRef, 0, &sParameterSet, &sParameterSetSize, &sParameterSetCount, 0);
        
        size_t pParameterSetSize,pParameterSetCount;
        const uint8_t *pParameterSet;
        OSStatus ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formateDescriptionRef, 1, &pParameterSet, &pParameterSetSize, &pParameterSetCount, 0);
        
        if(spsStatus == noErr && ppsStatus == noErr) {
            NSData * sps = [NSData dataWithBytes:sParameterSet length:sParameterSetSize];
            NSMutableData * spsData = [NSMutableData data];
            [spsData appendData:headerData];
            [spsData appendData:sps];
//            [self wite]
            [encoder writeDataToFile:spsData];
            NSData * pps = [NSData dataWithBytes:pParameterSet length:pParameterSetSize];
            NSMutableData * ppsData = [NSMutableData data];
            [ppsData appendData:headerData];
            [ppsData appendData:pps];
            [encoder writeDataToFile:spsData];
        }
        
        
    }else {
        NSLog(@"VEVideoEncoder::编码了一个非非非关键帧");

    }
    
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length,totalLength;
    char * dataPointer;
    status = CMBlockBufferGetDataPointer(blockBuffer, 0, &length, &totalLength, &dataPointer);
    
    if(status != noErr) {
        NSLog(@"VEVideoEncoder::CMBlockBufferGetDataPointer Error : %d!", (int)status);
        return;
    }
    
    size_t bufferOffset = 0;
    static const int avcHeaderLength  = 4;
    while (bufferOffset < totalLength - avcHeaderLength) {
        uint32_t nalUnitLength = 0;
        memcpy(&nalUnitLength, dataPointer+bufferOffset, avcHeaderLength);
        nalUnitLength = CFSwapInt32BigToHost(nalUnitLength);
        NSData * frameData = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset+avcHeaderLength) length:nalUnitLength];
        NSMutableData * outPutFrameData = [NSMutableData data];
        [outPutFrameData appendData:headerData];
        [outPutFrameData appendData:frameData];
        [encoder writeDataToFile:outPutFrameData];
        bufferOffset += avcHeaderLength+nalUnitLength;
        
    }
    
}
- (void)writeDataToFile:(NSMutableData *)data{
    [_fileHandle seekToEndOfFile];
    [_fileHandle writeData:data];
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
    
    if(output == self.videoDataOutput) {
        [self videoEncodeInputData:sampleBuffer forceKeyFrame:NO];
    }
    
}

- (BOOL)videoEncodeInputData:(CMSampleBufferRef)sampleBuffer forceKeyFrame:(BOOL)forceKeyFrame{
    
    if(_compressionSessionRef == NULL) {
        return NO;
    }
    
    if(sampleBuffer == nil) {
        return NO;
    }
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    NSDictionary * frameProperites = @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame:@(forceKeyFrame)};
    OSStatus status = VTCompressionSessionEncodeFrame(_compressionSessionRef, pixelBuffer, kCMTimeInvalid, kCMTimeInvalid, (__bridge CFDictionaryRef)frameProperites, NULL, NULL);
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::VTCompressionSessionEncodeFrame failed! status:%d", (int)status);
        return NO;
    }
    return YES;
}


@end
