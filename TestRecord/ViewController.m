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
#import "AQRecorderPro.h"
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


@interface ViewController ()

@property(weak, nonatomic) IBOutlet SCSiriWaveformView *waveView;

@property(nonatomic, strong) AQRecorder *recorder;
@property(nonatomic, strong) AQPlayer *player;
@property(nonatomic, strong) CADisplayLink *displaylink;

@property(nonatomic, strong) AQRecorderPro *microphone;
@property(nonatomic, strong) NSOutputStream *stream;
@property(nonatomic, strong) NSFileHandle *fileHandle;
@property(nonatomic, strong) NSString *filePath;
@property(nonatomic, strong) NSString *streamFilePath;

@end

@implementation ViewController

- (NSFileHandle *)fileHandle
{
    if (_fileHandle == nil) {
        _fileHandle = [NSFileHandle fileHandleForReadingAtPath:self.filePath];
    }
    return _fileHandle;
}

- (NSOutputStream *)stream
{
    if (_stream == nil) {
        self.stream = [[NSOutputStream alloc] initToFileAtPath:self.streamFilePath append:YES];
    }
    return _stream;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    kCodeTimeBegin;
    // Do any additional setup after loading the view.
    self.filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
    self.streamFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.stream.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
    NSLog(@"-----> %@", self.filePath);
    // 录音
    self.recorder = [[AQRecorder alloc] initAudioFilePath:self.filePath audioFormatType:AudioFormatLinearPCM];
    
    // 播放
    self.filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"iPhone.caf"];
    self.streamFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"iPhone.stream.caf"];
    self.player = [[AQPlayer alloc] initAudioFilePath:self.streamFilePath];
    
    // 录音Pro
    self.microphone = [[AQRecorderPro alloc] initAudioFilePath:self.filePath];
    [self.microphone setMeteringEnabled:YES];
    
        
    // 定时器读取音频的分贝值
//    _displaylink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateMeters)];
//    [_displaylink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    
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
    [self.stream open];
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (true) {
            [NSThread sleepForTimeInterval:1.0];
            NSData *data = [self.fileHandle readDataOfLength:4096];
            NSInteger lengthSet = [self.fileHandle offsetInFile];
            if (data.length == 0) {
                [self.stream close];
                self.stream = nil;
                self.fileHandle = nil;
                break;
            }
            [self.fileHandle seekToFileOffset:lengthSet];
            NSLog(@"readData => %@ -- %ld", data, lengthSet);
            [self.stream write:data.bytes maxLength:data.length];
            
        }
    });
    
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
    
    // FileHandle
    [self fileHandleReading];
}
- (IBAction)stopRecord1:(id)sender
{
    [self.microphone stopRecord];
    
    // FileHandle
    [self fileHandleClose];
}

- (void)fileHandleClose
{
    [self.stream close];
    self.stream = nil;
    self.fileHandle = nil;
}
- (void)fileHandleReading
{
    [self.stream open];
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        while (true) {
            if (self.stream == nil) {
                break;
            }
            NSData *data = [self.fileHandle readDataToEndOfFile];
            NSInteger lengthSet = [self.fileHandle offsetInFile];
            if (data.length) {
                NSLog(@"readData => %@ -- %ld", data, lengthSet);
                [self.stream write:data.bytes maxLength:data.length];
            }
        }
    });
}

- (void)cleanDisplaylink
{
    [self.displaylink invalidate];
    self.displaylink = nil;
}

- (void)updateMeters
{
//    CGFloat metersValue = [self.player getCurrentLevelMeter];
    CGFloat metersValue = [self.microphone  mPeakPowerValue];
    if (metersValue > 1 || isnan(metersValue)) {
        metersValue = 1;
    }
    
    __weak typeof (self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf.waveView updateWithLevel:metersValue];
    });
}

- (CGFloat)normalizedPowerLevelFromDecibels:(CGFloat)decibels
{
    if (decibels < -60.0f || decibels == 0.0f) {
        return 0.0f;
    }
    CGFloat value = powf((powf(10.0f, 0.05f * decibels) - powf(10.0f, 0.05f * -60.0f)) * (1.0f / (1.0f - powf(10.0f, 0.05f * -60.0f))), 1.0f / 2.0f);
    return value;
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

