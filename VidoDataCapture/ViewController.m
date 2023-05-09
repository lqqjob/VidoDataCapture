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
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *sourcePath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/test.h264"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if([fileManager fileExistsAtPath:sourcePath]) {
        [fileManager removeItemAtPath:sourcePath error:nil];
    }
    if(![fileManager createFileAtPath:sourcePath contents:nil attributes:nil]) {
        
    }
     _fileHandle= [NSFileHandle fileHandleForWritingAtPath:sourcePath];
    
    [self inInit];

    
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
    [self startVideoEncode];
    
}
- (void)createEncoder {
    int width = [UIScreen mainScreen].bounds.size.width;
    int height = [UIScreen mainScreen].bounds.size.height;
    OSStatus status = VTCompressionSessionCreate(NULL,width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, encodeOutPutDataCallback, (__bridge void*)self, &_compressionSessionRef);
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
    
    int32_t rotation = 0;
    CFNumberRef rotationDegrees = CFNumberCreate(NULL, kCFNumberSInt32Type, &rotation);
    VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_TransferFunction, rotationDegrees);
    
    // ProfileLevel，h264的协议等级，不同的清晰度使用不同的ProfileLevel。
    //质量水平
    // 1、Baseline Profile：基本画质。支持I/P 帧，只支持无交错（Progressive）和CAVLC；
    // 2、Extended profile：进阶画质。支持I/P/B/SP/SI 帧，只支持无交错（Progressive）和CAVLC；(用的少)
    // 3、Main profile：主流画质。提供I/P/B 帧，支持无交错（Progressive）和交错（Interlaced）， 也支持CAVLC 和CABAC 的支持；
    // 4、High profile：高级画质。在main Profile 的基础上增加了8x8内部预测、自定义量化、 无损视频编码和更多的YUV 格式；

    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_5_2);
    
    if (noErr != status)
    {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_ProfileLevel failed status:%d", (int)status);
        return;
    }
    //设置实时编码输出(避免延迟)
    //用来设置编码器的工作模式是实时还是离线
    //实时:延迟更低，但压缩效率会差一些，要求实时性高的场景需要开启
    //离线则编得慢些，延迟更大，但压缩效率会更高。本地录制视频文件可以使用离线模式
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
    
    //H.264压缩的熵编码模式。kVTH264EntropyMode_CAVLC(Context-based Adaptive Variable Length Coding) or kVTH264EntropyMode_CABAC(Context-based Adaptive Binary Arithmetic Coding)  CABAC通常以较高的计算开销为代价提供更好的压缩
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC);
    if(status != noErr) {
        NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_H264EntropyMode failed status:%d", (int)status);
        return;
    }
    
    //每个几个帧创建一个关键帧 100 表示每隔99帧创建一个关键帧
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_MaxKeyFrameInterval, (__bridge CFTypeRef)@(60));
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
    
    if ( @available(iOS 12.0, *)) {
        //在一个GOP里面的某一帧在解码时要依赖于前一个GOP中的某一些帧，这种GOP结构叫做Open-GOP。一般码流里面含有B帧的时候才会出现Open-GOP，Open-GOP以一个或多个B帧开始，参考之前GOP的P帧和当前GOP的I帧
        //我们通常用的是Close-GOP Close-GOP中的帧不可以参考其前后的其它GOP 一般以I帧开头
        status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_AllowOpenGOP,  kCFBooleanTrue);
        {
            NSLog(@"VEVideoEncoder::kVTCompressionPropertyKey_AllowOpenGOP failed status:%d", (int)status);
            return ;
        }
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

            [encoder writeDataToFile:spsData];
            
            NSData * pps = [NSData dataWithBytes:pParameterSet length:pParameterSetSize];
            NSMutableData * ppsData = [NSMutableData data];
            [ppsData appendData:headerData];
            [ppsData appendData:pps];
            [encoder writeDataToFile:ppsData];
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
    //用来设置硬性码率限制，实际做的就是设置码率的硬性限制是每秒码率不超过平均码率的 2 (kLimitToAverageBitRateFactor)倍
    CFArrayRef dataRateLimits = CFArrayCreate(NULL, nums, 2, &kCFTypeArrayCallBacks);
    status = VTSessionSetProperty(_compressionSessionRef, kVTCompressionPropertyKey_DataRateLimits, dataRateLimits);
    CFRelease(onSecond);
    CFRelease(bytePerSecond);
    CFRelease(dataRateLimits);
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
    
    self.videoInputDevice = self.backCamera;
}
- (void)createCaptureSession {
    self.captrueSession = [[AVCaptureSession alloc] init];
    [self.captrueSession beginConfiguration];
    
    //设置分辨率 720标清
    if([self.captrueSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
        [self.captrueSession setSessionPreset:AVCaptureSessionPreset1920x1080];
    }
    
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
    
    // 画面是向左旋转了90度，因为默认采集的视频是横屏的，需要我们进一步做调整。以下步骤添加在[session startRunning];之前即可，但是一定要在添加了 input 和 output之后～
    
    // 获取输入与输出之间的连接
    AVCaptureConnection *connection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    // 设置采集数据的方向
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    // 设置镜像效果镜像
    connection.videoMirrored = YES;
    
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
    [self.videoDataOutput setMinFrameDuration:CMTimeMake(1, 10)];//帧率 1秒钟10帧
    [self.videoDataOutput setSampleBufferDelegate:self queue:captureQueue];
    [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES];
    /**
     // key
     kCVPixelBufferPixelFormatTypeKey 指定解码后的图像格式
     // value
     kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange  : YUV420 用于标清视频[420v]
     kCVPixelFormatType_420YpCbCr8BiPlanarFullRange   : YUV422 用于高清视频[420f]
     kCVPixelFormatType_32BGRA : 输出的是BGRA的格式，适用于OpenGL和CoreImage

     区别：
     1、前两种是相机输出YUV格式，然后转成RGBA，最后一种是直接输出BGRA，然后转成RGBA;
     2、420v 输出的视频格式为NV12；范围： (luma=[16,235] chroma=[16,240])
     3、420f 输出的视频格式为NV12；范围： (luma=[0,255] chroma=[1,255])
     */
    [self.videoDataOutput setVideoSettings:@{
        (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }];
    
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    [self.audioDataOutput setSampleBufferDelegate:self queue:captureQueue];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    if(output == self.videoDataOutput) {
        //获取帧播放时间
        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
        //获取图片帧数据
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CIImage * ciImage = [CIImage imageWithCVImageBuffer:imageBuffer];
        UIImage * image = [UIImage imageWithCIImage:ciImage];
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
