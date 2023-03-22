# AQRecorder
 使用AudioQueue实现录音和播放



#### 录制

```objective-c
NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
NSLog(@"----- %@", filePath);
self.recorder = [[AQRecorder alloc] initAudioFilePath:filePath audioFormatType:AudioFormatLinearPCM];

// 开始录制
[self.recorder startRecord];

// 暂停录制
[self.recorder pauseRecord];

// 停止录制
[self.recorder stopRecord];
```

#### 播放

```objective-c
NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%.0f.%@", [NSDate timeIntervalSinceReferenceDate] * 1000.0, @"caf"]];
NSLog(@"----- %@", filePath);
NSString *filePath1 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"700911886073.caf"];
self.player = [[AQPlayer alloc] initAudioFilePath:filePath1];

// 开始播放
[self.player startPlayer];

// 暂停播放
[self.player pausePlayer];

// 停止播放
[self.player stopPlayer];
```

