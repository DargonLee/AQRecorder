//
//  AQRecorderPro.m
//  TestRecord
//
//  Created by Harlans on 2023/3/23.
//

#import "AQRecorderPro.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>

#define kDefaultSampleRate 8000.0
#define kDefaultChannels 1
#define kDefaultBitsPerChannel 16

// 1、定义用于管理状态的自定义结构
static const int kNumberBuffers = 3;
typedef struct AQRecorderStatePro {
    AudioStreamBasicDescription  mDataFormat;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    AudioFileID                  mAudioFile;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
    UInt32                       mEnableLevelMetering;
    double                       mLevelMeter;
} AQRecorderStatePro;

void AudioAQInputCallbackPro(void * __nullable            inUserData,
                          AudioQueueRef                   inAQ,
                          AudioQueueBufferRef             inBuffer,
                          const AudioTimeStamp *          inStartTime,
                          UInt32                          inNumberPacket,
                          const AudioStreamPacketDescription * __nullable inPacketDescs);

// 录制音频队列缓冲区大小
void SetDeriveBufferSize(AudioQueueRef audioQueue,
                         AudioStreamBasicDescription ASBDescription,
                         Float64  seconds,
                         UInt32   *outBufferSize)
{
    static const int maxBufferSize = 0x50000;
    
    int maxPacketSize = ASBDescription.mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    Float64 numBytesForTime = ASBDescription.mSampleRate * maxPacketSize * seconds;
    *outBufferSize = (UInt32)(numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize);
}

@interface AQRecorderPro()
{
    AQRecorderStatePro aqData;
    NSString *_audioFilePath;
}
@property(nonatomic,strong) NSOutputStream *stream;

@end

@implementation AQRecorderPro

- (void)dealloc
{
    [self freeAudioBuffers];
    AudioQueueDispose(aqData.mQueue, true);
}
- (void)freeAudioBuffers
{
    for(int i = 0; i < kNumberBuffers; i++)
    {
        OSStatus result = AudioQueueFreeBuffer(aqData.mQueue, aqData.mBuffers[i]);
        NSLog(@"AudioQueueFreeBuffer i = %d,result = %d", i, result);
    }
}

- (instancetype)initAudioFilePath:(NSString *_Nonnull)path
{
    if (self = [super init]) {
        _audioFilePath = [path copy];
        
        self.stream = [[NSOutputStream alloc] initToFileAtPath:path append:YES];
        [self setAudioSampleRate:8000.0 channels:1 bitsPerChannel:16];
        
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryMultiRoute error:nil];
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        
    }
    return self;
}

- (void)setAudioSampleRate:(Float64)sampleRate channels:(UInt32)channels bitsPerChannel:(UInt32)bitsPerChannel
{
    aqData.mDataFormat.mSampleRate = sampleRate > 0 ? sampleRate : kDefaultSampleRate;
    aqData.mDataFormat.mChannelsPerFrame = channels > 0 ? channels : kDefaultChannels;
    
    aqData.mDataFormat.mFormatID = kAudioFormatLinearPCM;
    aqData.mDataFormat.mBitsPerChannel = bitsPerChannel > 0 ? bitsPerChannel : kDefaultBitsPerChannel;
    aqData.mDataFormat.mBytesPerPacket =
    aqData.mDataFormat.mBytesPerFrame = (aqData.mDataFormat.mBitsPerChannel / 8) * aqData.mDataFormat.mChannelsPerFrame;
    aqData.mDataFormat.mFramesPerPacket = 1;
    aqData.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
}

- (void)processAudioQueueRef:(AudioQueueRef)inAudioQueue audioBuffer:(AudioQueueBufferRef)inBuffer audioTimeStamp:(const AudioTimeStamp *)inStartTime inNumberPacketDescriptions:(UInt32)inNumPackets audioPacketDesce:(const AudioStreamPacketDescription *)inPacketDesc


{
    if (aqData.mIsRunning == false) {
        return;
    }
    NSData *bufferData = [NSData dataWithBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];
    if (bufferData == nil) {
        return;
    }
    [self getVoiceVolume:bufferData];
    
    [self.stream write:bufferData.bytes maxLength:bufferData.length];
//    void *const audioBuffer = inBuffer->mAudioData;
//    printf("======> data: %p\n", audioBuffer);
//    OSStatus writeStatus = AudioFileWritePackets(aqData.mAudioFile,
//                                                 false,
//                                                 inBuffer->mAudioDataByteSize,
//                                                 inPacketDesc,
//                                                 aqData.mCurrentPacket,
//                                                 &inNumPackets,
//                                                 audioBuffer);
//    if (writeStatus == noErr) {
//        aqData.mCurrentPacket += inNumPackets;
//    }
    
    if (aqData.mIsRunning == false) {
        return;
    }
    
    AudioQueueEnqueueBuffer(inAudioQueue, inBuffer, 0, NULL);
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
    
    OSStatus queueStatus = AudioQueueNewInput(&aqData.mDataFormat, AudioAQInputCallbackPro, (__bridge void * _Nullable)(self), NULL, kCFRunLoopCommonModes, 0, &aqData.mQueue);
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
    
    // 设置缓冲区大小
    SetDeriveBufferSize(aqData.mQueue,
                     aqData.mDataFormat,
                     0.5,
                     &aqData.bufferByteSize);

    // 开启Metering
    UInt32 size = sizeof(aqData.mEnableLevelMetering);
    OSStatus status = AudioQueueSetProperty(aqData.mQueue, kAudioQueueProperty_EnableLevelMetering, &aqData.mEnableLevelMetering, size);
    if (status != noErr) {
        NSLog(@"开启Metering失败");
    }
    
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

- (void)setMeteringEnabled:(BOOL)meteringEnabled
{
    aqData.mEnableLevelMetering = meteringEnabled == YES ? 1 : 0;
}
- (BOOL)isMeteringEnabled
{
    BOOL result = aqData.mEnableLevelMetering == 1 ? YES : NO;
    return result;
}

- (BOOL)isRecording
{
    return aqData.mIsRunning ? YES : NO;;
}

- (void)startRecord
{
    // 开始录音
    if(![self prepareToRecord])
    {
        NSLog(@"准备录音失败");
        return;
    }
    [self.stream open];
    OSStatus startStatus = AudioQueueStart(aqData.mQueue, NULL);
    if (startStatus != noErr)
    {
        NSLog(@"开始录音失败：%d", startStatus);
        return;
    }
    NSLog(@"开始录音");
    aqData.mIsRunning = true;
}

- (void)stopRecord
{
    aqData.mIsRunning = false;
    [self.stream close];
    self.stream = nil;
    
    AudioQueueStop(aqData.mQueue, true);
    AudioFileClose(aqData.mAudioFile);
}

- (CGFloat)getCurrentLevelMeter
{
    return aqData.mLevelMeter;
}

- (void)getVoiceVolume:(NSData *)pcmData
{
    if(pcmData == nil)
    {
        return ;
    }
    
    if (self.currentLevelMeterDBValueBlock)
    {
        long pcmAllLenght = 0;
        short butterByte[pcmData.length/2];
        memcpy(butterByte, pcmData.bytes, pcmData.length);
        
        // 将 buffer 内容取出，进行平方和运算
        for(int i = 0; i < pcmData.length / 2; i++)
        {
            pcmAllLenght += butterByte[i] * butterByte[i];
        }
        double mean = pcmAllLenght / (double)pcmData.length;
        double volume = 10 * log10(mean);
        NSLog(@"分贝大小 %@", @(volume));
        self.currentLevelMeterDBValueBlock(volume);
    }
}

- (float)mPeakPowerValue
{
    float channelAvg = 0;
    int channelNumber = 0;
    UInt32 dataSize = sizeof(AudioQueueLevelMeterState) * aqData.mDataFormat.mChannelsPerFrame;
    AudioQueueLevelMeterState *levelMeters = (AudioQueueLevelMeterState *)malloc(dataSize);
    OSStatus status = AudioQueueGetProperty(aqData.mQueue, kAudioQueueProperty_CurrentLevelMeter, levelMeters, &dataSize);
    if (status != noErr)
    {
        NSLog(@"peakPowerMeter error %d", status);
        return 0;
    }
    channelAvg = levelMeters[channelNumber].mPeakPower;
//    for (int i = 0; i < dataSize; i++)
//    {
//        channelAvg += levelMeters[i].mAveragePower;  //取个平均值
//    }
    NSLog(@"getCurrentAudioPower %.2f", channelAvg);
    free(levelMeters);
    return channelAvg;
}

@end

void AudioAQInputCallbackPro(void * __nullable            inUserData,
                          AudioQueueRef                   inAQ,
                          AudioQueueBufferRef             inBuffer,
                          const AudioTimeStamp *          inStartTime,
                          UInt32                          inNumberPacket,
                          const AudioStreamPacketDescription * __nullable inPacketDescs) {
    
    AQRecorderPro * SELF = (__bridge AQRecorderPro *)inUserData;
    if (inNumberPacket > 0)
    {
        [SELF processAudioQueueRef:inAQ audioBuffer:inBuffer audioTimeStamp:inStartTime inNumberPacketDescriptions:inNumberPacket audioPacketDesce:inPacketDescs];
    }
}
