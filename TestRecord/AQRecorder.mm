//
//  AQRecorderManager.m
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import "AQRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>

#define kDefaultSampleRate 8000.0
#define kDefaultChannels 1
#define kDefaultBitsPerChannel 16

// 1、定义用于管理状态的自定义结构
static const int kNumberBuffers = 3;
typedef struct AQRecorderState {
    AudioStreamBasicDescription  mDataFormat;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    AudioFileID                  mAudioFile;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
} AQRecorderState;

// 2、编写录制音频队列回调
static void HandleInputBuffer (
    void                                *aqData,
    AudioQueueRef                       inAQ,
    AudioQueueBufferRef                 inBuffer,
    const AudioTimeStamp                *inStartTime,
    UInt32                              inNumPackets,
    const AudioStreamPacketDescription  *inPacketDesc
                               )
{
    NSLog(@"----->音频队列回调");
    AQRecorderState *pAqData = (AQRecorderState *) aqData;
    
    if (inNumPackets == 0 &&
        pAqData->mDataFormat.mBytesPerPacket != 0) {
        inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
    }
    
    // 3、将音频队列缓冲区写入磁盘
    // 要写入音频文件的新音频数据
    // NSData *pcmData = [NSData dataWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
    void *const audioBuffer = inBuffer->mAudioData;
    printf("======> data: %p\n", audioBuffer);
    OSStatus writeStatus = AudioFileWritePackets(pAqData->mAudioFile,
                                                 false,
                                                 inBuffer->mAudioDataByteSize,
                                                 inPacketDesc,
                                                 pAqData->mCurrentPacket,
                                                 &inNumPackets,
                                                 audioBuffer);
    if (writeStatus == noErr) {
        pAqData->mCurrentPacket += inNumPackets;
    }
    
    if (pAqData->mIsRunning == false) {
        return;
    }
    
    AudioQueueEnqueueBuffer (
                             pAqData->mQueue,
                             inBuffer,
                             0,
                             NULL
                             );
}

// 4、录制音频队列缓冲区大小
void DeriveBufferSize (
                       AudioQueueRef audioQueue,
                       AudioStreamBasicDescription &ASBDescription,
                       Float64  seconds,
                       UInt32   *outBufferSize
                       )
{
    static const int maxBufferSize = 0x50000;
    
    int maxPacketSize = ASBDescription.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    
    Float64 numBytesForTime = ASBDescription.mSampleRate * maxPacketSize * seconds;
    *outBufferSize = UInt32 (numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize);
}

// 5、为音频文件设置魔术饼干
OSStatus SetMagicCookieForFile (AudioQueueRef inQueue, AudioFileID inFile)
{
    OSStatus result = noErr;
    UInt32 cookieSize;
    if (AudioQueueGetPropertySize(inQueue, kAudioQueueProperty_MagicCookie, &cookieSize) == noErr) {
            char* magicCookie = (char *)malloc(cookieSize);
            if (AudioQueueGetProperty (inQueue, kAudioQueueProperty_MagicCookie, magicCookie, &cookieSize ) == noErr)
                result = AudioFileSetProperty(inFile, kAudioFilePropertyMagicCookieData, cookieSize, magicCookie);
            free(magicCookie);
        }
    return result;
}

@interface AQRecorder()
{
    AQRecorderState aqData;
    NSString *_audioFilePath;
    BOOL _pauseing;
}
@property (nonatomic, strong) CADisplayLink *displaylink;
@end

@implementation AQRecorder

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path audioFormatType:(AudioFormatType)type
{
    if (self = [super init]) {
        _audioFilePath = [path copy];
        
        [self setAudioFormatType:type sampleRate:8000.0 channels:1 bitsPerChannel:16];
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryMultiRoute error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
        _displaylink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMeters)];
        [_displaylink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)setAudioFormatType:(AudioFormatType)audioFormatType
                sampleRate:(Float64)sampleRate
                  channels:(UInt32)channels
            bitsPerChannel:(UInt32)bitsPerChannel
{
    aqData.mDataFormat.mSampleRate = sampleRate > 0 ? sampleRate : kDefaultSampleRate;
    aqData.mDataFormat.mChannelsPerFrame = channels > 0 ? channels : kDefaultChannels;
    
    if (audioFormatType == AudioFormatLinearPCM) {
        aqData.mDataFormat.mFormatID = kAudioFormatLinearPCM;
        aqData.mDataFormat.mBitsPerChannel = bitsPerChannel > 0 ? bitsPerChannel : kDefaultBitsPerChannel;
        aqData.mDataFormat.mBytesPerPacket =
        aqData.mDataFormat.mBytesPerFrame = (aqData.mDataFormat.mBitsPerChannel / 8) * aqData.mDataFormat.mChannelsPerFrame;
        aqData.mDataFormat.mFramesPerPacket = 1;
        aqData.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    } else if (audioFormatType == AudioFormatMPEG4AAC) {
        aqData.mDataFormat.mFormatID = kAudioFormatMPEG4AAC;
        aqData.mDataFormat.mFormatFlags = kMPEG4Object_AAC_Main;
        
    }
}

- (BOOL)prepareToRecord
{
    // 创建录音存储文件
    CFURLRef audioFileURL = CFURLCreateWithString(kCFAllocatorDefault, (CFStringRef)_audioFilePath, NULL);
    OSStatus fileStatus = AudioFileCreateWithURL(audioFileURL,
                                                 kAudioFileCAFType,
                                                 &aqData.mDataFormat,
                                                 kAudioFileFlags_EraseFile,
                                                 &aqData.mAudioFile);
    CFRelease(audioFileURL);
    if (fileStatus != noErr)
    {
        NSLog(@"创建文件失败：%d", fileStatus);
        return NO;
    }
    
    // 创建音频队列
    OSStatus queueStatus = AudioQueueNewInput(&aqData.mDataFormat,
                       HandleInputBuffer,
                       &aqData,
                       NULL,
                       kCFRunLoopCommonModes,
                       0,
                       &aqData.mQueue);
    if (queueStatus != noErr)
    {
        NSLog(@"创建音频队列失败: %d", queueStatus);
        return NO;
    }
    
    UInt32 dataFormatSize = sizeof(aqData.mDataFormat);
    AudioQueueGetProperty(aqData.mQueue,
                          kAudioQueueProperty_StreamDescription,
                          &aqData.mDataFormat,
                          &dataFormatSize);
    
    // 设置magic cookie
    if (aqData.mDataFormat.mFormatID != kAudioFormatLinearPCM)
    {
        SetMagicCookieForFile(aqData.mQueue, aqData.mAudioFile);
    }
    
    // 设置缓冲区大小
    DeriveBufferSize(aqData.mQueue,
                     aqData.mDataFormat,
                     0.5,
                     &aqData.bufferByteSize);
        
    // 创建音频队列缓冲区
    aqData.mCurrentPacket = 0;
    for (int i = 0; i < kNumberBuffers; ++i)
    {
        OSStatus allocBufferStatus = AudioQueueAllocateBuffer(aqData.mQueue,
                                                              aqData.bufferByteSize,
                                                              &aqData.mBuffers[i]);
        if (allocBufferStatus != noErr)
        {
            NSLog(@"分配缓冲区失败：%d", allocBufferStatus);
            return NO;
        }
        
        OSStatus enqueueStatus = AudioQueueEnqueueBuffer(aqData.mQueue,
                                                         aqData.mBuffers[i],
                                                         0,
                                                         NULL);
        if (enqueueStatus != noErr)
        {
            NSLog(@"缓冲区排队失败：%d", enqueueStatus);
            return NO;
        }
    }
    
    return YES;
}

- (void)startRecord
{
    if (!_pauseing)
    {
        if (![self prepareToRecord])
        {
            NSLog(@"准备录音失败！！！");
            return;
        }
    }
    
    // 开始录音
    OSStatus startStatus = AudioQueueStart(aqData.mQueue, NULL);
    if (startStatus != noErr)
    {
        NSLog(@"开始录音失败：%d", startStatus);
        return;
    }
    NSLog(@"开始录音---->%d<----", startStatus);
    aqData.mIsRunning = true;
    
}

- (BOOL)isRecording
{
    return aqData.mIsRunning ? YES : NO;;
}

- (void)pauseRecord
{
    OSStatus startStatus = AudioQueuePause(aqData.mQueue);
    if (startStatus != noErr)
    {
        NSLog(@"录音暂停失败：%d", startStatus);
        return;
    }
    _pauseing = YES;
}

- (void)stopRecord
{
    aqData.mIsRunning = false;
    AudioQueueStop(aqData.mQueue, true);
    
    // 录音结束后再次调用magic cookies，一些编码器会在录音停止后更新magic cookies数据
    if (aqData.mDataFormat.mFormatID != kAudioFormatLinearPCM)
    {
        SetMagicCookieForFile(aqData.mQueue, aqData.mAudioFile);
    }
    
    AudioQueueDispose(aqData.mQueue, true);
    AudioFileClose(aqData.mAudioFile);
}

- (void)updateMeters
{
    CGFloat normalizedValue = [self _normalizedPowerLevelFromDecibels:[self getCurrentPower]];
    if (self.normalizedValueBlock) {
        self.normalizedValueBlock(normalizedValue);
    }
}

- (CGFloat)_normalizedPowerLevelFromDecibels:(CGFloat)decibels
{
    if (decibels < -60.0f || decibels == 0.0f) {
        return 0.0f;
    }
    return powf((powf(10.0f, 0.05f * decibels) - powf(10.0f, 0.05f * -60.0f)) * (1.0f / (1.0f - powf(10.0f, 0.05f * -60.0f))), 1.0f / 2.0f);
}

- (void)cleanDisplayLink
{
    if (self.displaylink) {
        [self.displaylink invalidate];
        self.displaylink = nil;
    }
}

- (CGFloat)getCurrentPower
{
    UInt32 dataSize = sizeof(AudioQueueLevelMeterState) * aqData.mDataFormat.mChannelsPerFrame;
    AudioQueueLevelMeterState *levels = (AudioQueueLevelMeterState*)malloc(dataSize);
    OSStatus rc = AudioQueueGetProperty(aqData.mQueue, kAudioQueueProperty_CurrentLevelMeterDB, levels, &dataSize);
    if (rc)
    {
        NSLog(@"NoiseLeveMeter>>takeSample - AudioQueueGetProperty(CurrentLevelMeter) returned %d", rc);
    }
    
    CGFloat channelAvg = 0;
    for (int i = 0; i < dataSize; i++)
    {
        channelAvg += levels[i].mAveragePower;
    }
    free(levels);
    
    return channelAvg ;
}

- (void)dealloc
{
    NSLog(@"--- dealloc ---");
    AudioQueueStop(aqData.mQueue, true);
    AudioQueueDispose(aqData.mQueue, true);
    AudioFileClose(aqData.mAudioFile);
}

@end
