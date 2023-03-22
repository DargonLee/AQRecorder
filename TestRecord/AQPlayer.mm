//
//  AQPlayer.m
//  TestRecord
//
//  Created by Harlan on 2023/3/19.
//

#import "AQPlayer.h"
#include <string>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudioTypes.h>
#import <AVFoundation/AVFoundation.h>

// 1、定义用于管理状态的自定义结构
static const int kNumberBuffers = 3;
typedef struct AQPlayerState {
    AudioStreamBasicDescription   mDataFormat;
    AudioQueueRef                 mQueue;
    AudioQueueBufferRef           mBuffers[kNumberBuffers];
    AudioFileID                   mAudioFile;
    UInt32                        bufferByteSize;
    SInt64                        mCurrentPacket;
    UInt32                        mNumPacketsToRead;
    AudioStreamPacketDescription  *mPacketDescs;
    bool                          mIsRunning;
} AQPlayerState;

// 2、编写播放音频队列回调
static void HandleOutputBuffer (
                                void                 *aqData,
                                AudioQueueRef        inAQ,
                                AudioQueueBufferRef  inBuffer
                                ) {
    NSLog(@"----->音频队列回调");
    AQPlayerState *pAqData = (AQPlayerState *) aqData;
    if (pAqData->mIsRunning == 0) {
        NSLog(@"------> mIsRunning error");
        return;
    }

//    UInt32 outNumPackets = 0;
//    if (pAqData->mDataFormat.mBytesPerPacket != 0) {
//        outNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
//    }
    
    
    //    OSStatus readStatus = AudioFileReadPackets (
    //        pAqData->mAudioFile,
    //        false,
    //        &numBytesReadFromFile,
    //        pAqData->mPacketDescs,
    //        pAqData->mCurrentPacket,
    //        &outNumPackets,
    //        inBuffer->mAudioData
    //    );
    
    // 3、从文件读入音频队列缓冲区
    UInt32 numBytesReadFromFile = 2048;
    UInt32 numPackets = pAqData->mNumPacketsToRead;
    
    void *const audioBuffer = inBuffer->mAudioData;
    printf("======> data: %p\n", audioBuffer);
    OSStatus readStatus = AudioFileReadPacketData(pAqData->mAudioFile,
                                                  false,
                                                  &numBytesReadFromFile,
                                                  pAqData->mPacketDescs,
                                                  pAqData->mCurrentPacket,
                                                  &numPackets,
                                                  audioBuffer);
//    OSStatus readStatus = AudioFileReadPackets (pAqData->mAudioFile,
//                                                false,
//                                                &numBytesReadFromFile,
//                                                pAqData->mPacketDescs,
//                                                pAqData->mCurrentPacket,
//                                                &numPackets,
//                                                audioBuffer);
    if (readStatus != noErr) {
        NSLog(@"------> readStatus error");
        return;
    }
    
    if (numPackets > 0)
    {
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        // 4、对音频队列缓冲区进行排队
        AudioQueueEnqueueBuffer (pAqData->mQueue,
                                 inBuffer,
                                 (pAqData->mPacketDescs ? numPackets : 0),
                                 pAqData->mPacketDescs);
        pAqData->mCurrentPacket += numPackets;
        
    }
    else
    {
        // 5、停止音频队列
        AudioQueueStop (
            pAqData->mQueue,
            false
        );
        pAqData->mIsRunning = false;
    }
}

// 6、编写函数以派生播放音频队列缓冲区大小
void DeriveBufferSize (
    AudioStreamBasicDescription &ASBDesc,
    UInt32                      maxPacketSize,
    Float64                     seconds,
    UInt32                      *outBufferSize,
    UInt32                      *outNumPacketsToRead
) {
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000;
 
    if (ASBDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime =
            ASBDesc.mSampleRate / ASBDesc.mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        *outBufferSize =
            maxBufferSize > maxPacketSize ?
                maxBufferSize : maxPacketSize;
    }
 
    if (
        *outBufferSize > maxBufferSize &&
        *outBufferSize > maxPacketSize
    )
        *outBufferSize = maxBufferSize;
    else {
        if (*outBufferSize < minBufferSize)
            *outBufferSize = minBufferSize;
    }
 
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;
}

// 为音频文件设置魔术饼干
OSStatus SetMagicCookieForFileRead (AudioQueueRef inQueue, AudioFileID inFile)
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

@interface AQPlayer()
{
    AQPlayerState aqData;
    NSString *_audioFilePath;
}
@end

@implementation AQPlayer
- (instancetype)initAudioFilePath:(NSString *_Nonnull)path
{
    if (self = [super init]) {
        _audioFilePath = [path copy];
    }
    return self;
}

- (BOOL)prepareToPlay
{
    // 获取音频文件的 CFURL 对象
    const char *filePath;
    filePath = [_audioFilePath UTF8String];
    CFURLRef audioFileURL = CFURLCreateFromFileSystemRepresentation (NULL, (const UInt8 *) filePath, strlen (filePath), false);
    
    // 打开音频文件
    OSStatus fileStatus = AudioFileOpenURL(audioFileURL, kAudioFileReadPermission, 0, &aqData.mAudioFile);
    CFRelease (audioFileURL);
    if (fileStatus != noErr)
    {
        NSLog(@"打开文件失败：%d", fileStatus);
        return NO;
    }
    
    // 获取文件的音频数据格式
    UInt32 dataFormatSize = sizeof (aqData.mDataFormat);
    AudioFileGetProperty (
        aqData.mAudioFile,
        kAudioFilePropertyDataFormat,
        &dataFormatSize,
        &aqData.mDataFormat
    );
    
    // 创建播放音频队列
    OSStatus queueStatus = AudioQueueNewOutput (
        &aqData.mDataFormat,
        HandleOutputBuffer,
        &aqData,
        CFRunLoopGetCurrent (),
        kCFRunLoopCommonModes,
        0,
        &aqData.mQueue
    );
    if (queueStatus != noErr)
    {
        NSLog(@"创建音频队列失败: %d", queueStatus);
        return NO;
    }
    
    // 设置播放音频队列的大小
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof (maxPacketSize);
    AudioFileGetProperty (
        aqData.mAudioFile,
        kAudioFilePropertyPacketSizeUpperBound,
        &propertySize,
        &maxPacketSize
    );
     
    DeriveBufferSize (
        aqData.mDataFormat,
        maxPacketSize,
        0.5,
        &aqData.bufferByteSize,
        &aqData.mNumPacketsToRead
    );

    // 为数据包描述阵列分配内存
    bool isFormatVBR = (
        aqData.mDataFormat.mBytesPerPacket == 0 ||
        aqData.mDataFormat.mFramesPerPacket == 0
    );
     
    if (isFormatVBR) {
        aqData.mPacketDescs =
          (AudioStreamPacketDescription*) malloc (
            aqData.mNumPacketsToRead * sizeof (AudioStreamPacketDescription)
          );
    } else {
        aqData.mPacketDescs = NULL;
    }
    
    // 设置magic cookie
    if (aqData.mDataFormat.mFormatID != kAudioFormatLinearPCM)
    {
        SetMagicCookieForFileRead(aqData.mQueue, aqData.mAudioFile);
    }
    // 分配和主音频队列缓冲区
    aqData.mCurrentPacket = 0;
    for (int i = 0; i < kNumberBuffers; ++i)
    {
        AudioQueueAllocateBuffer (
            aqData.mQueue,
            aqData.bufferByteSize,
            &aqData.mBuffers[i]
        );
     
        HandleOutputBuffer (
            &aqData,
            aqData.mQueue,                    
            aqData.mBuffers[i]
        );
    }
    
    return YES;
}

- (void)startPlayer
{
    if (aqData.mIsRunning == false) {
        aqData.mIsRunning = true;
        if (![self prepareToPlay]) {
            NSLog(@"播放失败");
            return;
        }
    }
    AudioQueueStart (
        aqData.mQueue,
        NULL
    );
     
    do {
        CFRunLoopRunInMode (
            kCFRunLoopDefaultMode,
            0.25,
            false
        );
    } while (aqData.mIsRunning);
     
    CFRunLoopRunInMode (
        kCFRunLoopDefaultMode,
        1,
        false
    );
}

- (void)pausePlayer
{
    OSStatus startStatus = AudioQueuePause(aqData.mQueue);
    if (startStatus != noErr)
    {
        NSLog(@"录音暂停失败：%d", startStatus);
        return;
    }
}

- (void)stopPlayer
{
    AudioQueueDispose (
        aqData.mQueue,
        true
    );
    AudioFileClose (aqData.mAudioFile);
    free (aqData.mPacketDescs);
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

@end
