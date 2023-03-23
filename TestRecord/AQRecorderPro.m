//
//  AQRecorderPro.m
//  TestRecord
//
//  Created by Harlans on 2023/3/23.
//

#import "AQRecorderPro.h"
#import <AudioToolbox/AudioToolbox.h>
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
    double                       mLevelMeter;
} AQRecorderStatePro;

void AudioAQInputCallbackPro(void * __nullable               inUserData,
                          AudioQueueRef                   inAQ,
                          AudioQueueBufferRef             inBuffer,
                          const AudioTimeStamp *          inStartTime,
                          UInt32                          inNumberPacket,
                          const AudioStreamPacketDescription * __nullable inPacketDescs);

@interface AQRecorderPro()
{
    AQRecorderStatePro aqData;
    NSString *_audioFilePath;
}
@property (nonatomic, assign) BOOL isBufferAlloc;
@property(nonatomic,strong) NSOutputStream *stream;
@end

@implementation AQRecorderPro

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
    aqData.mDataFormat.mBytesPerFrame = (aqData.mDataFormat.mBitsPerChannel / 8) * aqData.mDataFormat.mChannelsPerFrame;
    aqData.mDataFormat.mFramesPerPacket = 1;
    aqData.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
}
/*
 AudioQueueRef                   inAQ,
 AudioQueueBufferRef             inBuffer,
 const AudioTimeStamp *          inStartTime,
 UInt32                          inNumberPacketDescriptions,
 const AudioStreamPacketDescription * __nullable inPacketDescs
 */
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
    const void *audioBuffer = bufferData.bytes;
    printf("======> data: %p\n", audioBuffer);
    OSStatus writeStatus = AudioFileWritePackets(aqData.mAudioFile,
                                                 false,
                                                 inBuffer->mAudioDataByteSize,
                                                 inPacketDesc,
                                                 aqData.mCurrentPacket,
                                                 &inNumPackets,
                                                 audioBuffer);
    
    if (writeStatus == noErr) {
        aqData.mCurrentPacket += inNumPackets;
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
    return [self allocAudioBuffers];
}

- (BOOL)allocAudioBuffers
{
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
- (void)freeAudioBuffers
{
    for(int i = 0; i < kNumberBuffers; i++)
    {
        OSStatus result = AudioQueueFreeBuffer(aqData.mQueue, aqData.mBuffers[i]);
        NSLog(@"AudioQueueFreeBuffer i = %d,result = %d", i, result);
    }
    AudioQueueDispose(aqData.mQueue, YES);
}

- (BOOL)isRecording
{
    return aqData.mIsRunning ? YES : NO;;
}

- (void)startRecord
{
    // 开始录音
    [self.stream open];
    OSStatus startStatus = AudioQueueStart(aqData.mQueue, NULL);
    if (startStatus != noErr)
    {
        NSLog(@"开始录音失败：%d", startStatus);
        return;
    }
    NSLog(@"开始录音---->%d<----", startStatus);
    aqData.mIsRunning = true;
}

- (void)stopRecord
{
    aqData.mIsRunning = false;
    [self freeAudioBuffers];
    [self.stream close];
    self.stream = nil;
    
    AudioQueueStop(aqData.mQueue, true);
    AudioQueueDispose(aqData.mQueue, true);
    AudioFileClose(aqData.mAudioFile);
}

- (CGFloat)getCurrentLevelMeter
{
    return aqData.mLevelMeter;
}

- (void)getVoiceVolume:(NSData *)pcmData
{
    if(pcmData ==nil)
    {
        return ;
    }
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
    aqData.mLevelMeter = volume;
}

- (void)writeWaveHead:(NSData *)audioData
{
    long sampleRate = aqData.mDataFormat.mSampleRate;
    Byte waveHead[44];
    waveHead[0] = 'R';
    waveHead[1] = 'I';
    waveHead[2] = 'F';
    waveHead[3] = 'F';
    
    long totalDatalength = [audioData length] + 44;
    waveHead[4] = (Byte)(totalDatalength & 0xff);
    waveHead[5] = (Byte)((totalDatalength >> 8) & 0xff);
    waveHead[6] = (Byte)((totalDatalength >> 16) & 0xff);
    waveHead[7] = (Byte)((totalDatalength >> 24) & 0xff);
    
    waveHead[8] = 'W';
    waveHead[9] = 'A';
    waveHead[10] = 'V';
    waveHead[11] = 'E';
    
    waveHead[12] = 'f';
    waveHead[13] = 'm';
    waveHead[14] = 't';
    waveHead[15] = ' ';
    
    waveHead[16] = 16;  //size of 'fmt '
    waveHead[17] = 0;
    waveHead[18] = 0;
    waveHead[19] = 0;
    
    waveHead[20] = 1;   //format
    waveHead[21] = 0;
    
    waveHead[22] = 1;   //chanel
    waveHead[23] = 0;
    
    waveHead[24] = (Byte)(sampleRate & 0xff);
    waveHead[25] = (Byte)((sampleRate >> 8) & 0xff);
    waveHead[26] = (Byte)((sampleRate >> 16) & 0xff);
    waveHead[27] = (Byte)((sampleRate >> 24) & 0xff);
    
    long byteRate = sampleRate * 2 * (16 >> 3);;
    waveHead[28] = (Byte)(byteRate & 0xff);
    waveHead[29] = (Byte)((byteRate >> 8) & 0xff);
    waveHead[30] = (Byte)((byteRate >> 16) & 0xff);
    waveHead[31] = (Byte)((byteRate >> 24) & 0xff);
    
    waveHead[32] = 2*(16 >> 3);
    waveHead[33] = 0;
    
    waveHead[34] = 16;
    waveHead[35] = 0;
    
    waveHead[36] = 'd';
    waveHead[37] = 'a';
    waveHead[38] = 't';
    waveHead[39] = 'a';
    
    long totalAudiolength = [audioData length];
    
    waveHead[40] = (Byte)(totalAudiolength & 0xff);
    waveHead[41] = (Byte)((totalAudiolength >> 8) & 0xff);
    waveHead[42] = (Byte)((totalAudiolength >> 16) & 0xff);
    waveHead[43] = (Byte)((totalAudiolength >> 24) & 0xff);
    
    NSData *data = [NSData dataWithBytes:&waveHead  length:sizeof(waveHead)];
    [self.stream write:[data bytes] maxLength:data.length];
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
