//
//  ViewController.m
//  TestRecord
//
//  Created by Harlan on 2023/3/18.
//

#import "ViewController.h"
#import "AQRecorder.h"
#import "AQPlayer.h"
#import "SCSiriWaveformView.h"
#import "DBAudioMicrophone.h"
#import <mach/mach_time.h>

double MachTimeToSecs(uint64_t time)
{
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    return (double)time * (double)timebase.numer /
    (double)timebase.denom / NSEC_PER_SEC;
}

#define kCodeTimeBegin uint64_t begin = mach_absolute_time()

#define kCodeTimeEnd uint64_t end = mach_absolute_time(); \
NSLog(@"Time taken to doSomething %g s", MachTimeToSecs(end - begin));
/*
 - (void)profileDoSomething
 {
     uint64_t begin = mach_absolute_time();
     [self doSomething];
     uint64_t end = mach_absolute_time();
     NSLog(@"Time taken to doSomething %g s",
     MachTimeToSecs(end - begin));
 }
 */

@interface ViewController ()<DBAudioMicrophoneDelegate>

@property(weak, nonatomic) IBOutlet SCSiriWaveformView *waveView;
@property(nonatomic, strong) AQRecorder *recorder;
@property(nonatomic, strong) AQPlayer *player;
@property(nonatomic, strong) CADisplayLink *displaylink;

@property(nonatomic, strong) DBAudioMicrophone *microphone;
@property(nonatomic,strong) NSOutputStream *stream;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    kCodeTimeBegin;
    // Do any additional setup after loading the view.
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
    NSLog(@"----- %@", filePath);
    // 录音
    self.recorder = [[AQRecorder alloc] initAudioFilePath:filePath audioFormatType:AudioFormatMPEG4AAC];
    
    // 播放
    NSString *filePath1 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"701100889296.caf"];
    self.player = [[AQPlayer alloc] initAudioFilePath:filePath1];
    
    // 定时器读取音频的分贝值
    _displaylink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMeters)];
    _displaylink.preferredFramesPerSecond = 1;
    [_displaylink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
    self.microphone = [[DBAudioMicrophone alloc] initWithSampleRate:16000 numerOfChannel:1];
    self.microphone.delegate = self;
    NSString *filePath2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"microphone.caf"];
    self.stream = [[NSOutputStream alloc] initToFileAtPath:filePath2 append:YES];
    
    // 分贝图
    [self.waveView setWaveColor:[UIColor redColor]];
    [self.waveView setPrimaryWaveLineWidth:3.0f];
    [self.waveView setSecondaryWaveLineWidth:1.0];
    
    kCodeTimeEnd;
}

- (IBAction)begin:(id)sender
{
    [self.recorder startRecord];
}
- (IBAction)pause:(id)sender
{
    [self.recorder pauseRecord];
}
- (IBAction)stop:(id)sender
{
    [self.recorder stopRecord];
    [self cleanDisplaylink];
}
- (IBAction)startPlay:(id)sender
{
    [self.player startPlayer];
}
- (IBAction)pausePlay:(id)sender
{
    [self.player pausePlayer];
}
- (IBAction)stopPlay:(id)sender
{
    [self.player stopPlayer];
    
    [self cleanDisplaylink];
}
- (IBAction)startRecord1:(id)sender
{
    [self.microphone startRecord];
    [self.stream open];
}
- (IBAction)pauseRecord1:(id)sender
{
    [self.microphone pause];
}
- (IBAction)stopRecord1:(id)sender
{
    [self.microphone stop];
    [self.stream close];
    self.stream = nil;
}

- (void)cleanDisplaylink
{
    [self.displaylink invalidate];
    self.displaylink = nil;
}

- (void)updateMeters
{
//    CGFloat metersValue = [self.player getCurrentLevelMeter];
    CGFloat metersValue = [self.recorder getCurrentLevelMeter];
    NSLog(@"metersValue -> %f", metersValue);
    CGFloat value = metersValue/100;
    CGFloat normalizedValue = [self normalizedPowerLevelFromDecibels:metersValue];
    NSLog(@"normalizedValue -> %f", value);
    [self.waveView updateWithLevel:metersValue];
}

- (CGFloat)normalizedPowerLevelFromDecibels:(CGFloat)decibels
{
    if (decibels < -60.0f || decibels == 0.0f) {
        return 0.0f;
    }
    CGFloat value = powf((powf(10.0f, 0.05f * decibels) - powf(10.0f, 0.05f * -60.0f)) * (1.0f / (1.0f - powf(10.0f, 0.05f * -60.0f))), 1.0f / 2.0f);
    return value;
}

// MARK: DBAudioMicrophoneDelegate
- (void)audioMicrophone:(DBAudioMicrophone *)microphone hasAudioPCMByte:(Byte *)pcmByte audioByteSize:(UInt32)byteSize
{
    NSData *data = [NSData dataWithBytes:pcmByte length:byteSize];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self writeWaveHead:data sampleRate:44100];
    });
    [self.stream write:[data bytes] maxLength:data.length];
}

- (void)audioCallBackVoiceGrade:(NSInteger)grade
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"dbValue:%@",@(grade));
        
        NSUInteger volumeDB = grade;
        static NSInteger index = 0;
        index++;
        if (index == 1) {
            index = 0;
        }else {
            return;
        }
        
        CGFloat normalizedValue = [self normalizedPowerLevelFromDecibels:volumeDB];
        NSLog(@"normalizedValue:%@",@(normalizedValue));
        [self.waveView updateWithLevel:volumeDB/100];
        
    });

}

- (void)writeWaveHead:(NSData *)audioData sampleRate:(long)sampleRate
{
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

