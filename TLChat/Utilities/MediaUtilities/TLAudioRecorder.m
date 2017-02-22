
//
//  TLAudioRecorder.m
//  TLChat
//
//  Created by 李伯坤 on 16/7/11.
//  Copyright © 2016年 李伯坤. All rights reserved.
//

#import "TLAudioRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import "lame.h"

#define     PATH_RECFILE        [[NSFileManager cachesPath] stringByAppendingString:@"/rec.caf"]

#define     PATH_MP3FILE        [[NSFileManager cachesPath] stringByAppendingString:@"/rec.mp3"]

@interface TLAudioRecorder () <AVAudioRecorderDelegate>

@property (nonatomic, strong) AVAudioRecorder *recorder;

@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) void (^volumeChangedBlock)(CGFloat valume);
@property (nonatomic, strong) void (^completeBlock)(NSString *path, CGFloat time);
@property (nonatomic, strong) void (^cancelBlock)();

@property (nonatomic,assign) CGFloat time;

@end

@implementation TLAudioRecorder

+ (TLAudioRecorder *)sharedRecorder
{
    static dispatch_once_t once;
    static TLAudioRecorder *audioRecorder;
    dispatch_once(&once, ^{
        audioRecorder = [[TLAudioRecorder alloc] init];
    });
    return audioRecorder;
}

- (void)startRecordingWithVolumeChangedBlock:(void (^)(CGFloat volume))volumeChanged
                               completeBlock:(void (^)(NSString *path, CGFloat time))complete
                                 cancelBlock:(void (^)())cancel;
{
    self.volumeChangedBlock = volumeChanged;
    self.completeBlock = complete;
    self.cancelBlock = cancel;
    if ([[NSFileManager defaultManager] fileExistsAtPath:PATH_RECFILE]) {
        [[NSFileManager defaultManager] removeItemAtPath:PATH_RECFILE error:nil];
    }
    [self.recorder prepareToRecord];
    [self.recorder record];
    
    if (self.timer && self.timer.isValid) {
        [self.timer invalidate];
    }
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer bk_scheduledTimerWithTimeInterval:0.5 block:^(NSTimer *timer) {
        [weakSelf.recorder updateMeters];
        float peakPower = pow(10, (0.05 * [weakSelf.recorder peakPowerForChannel:0]));
        if (weakSelf && weakSelf.volumeChangedBlock) {
            weakSelf.volumeChangedBlock(peakPower);
        }
    } repeats:YES];
}

- (void)stopRecording
{
    [self.timer invalidate];
    CGFloat time = self.recorder.currentTime;
    self.time = time;
    [self.recorder stop];
    if (self.completeBlock) {
        self.completeBlock(PATH_RECFILE, time);
        self.completeBlock = nil;
    }
}

- (void)cancelRecording
{
    [self.timer invalidate];
    [self.recorder stop];
    if (self.cancelBlock) {
        self.cancelBlock();
        self.cancelBlock = nil;
    }
}

#pragma mark - # Delegate
//MARK: AVAudioRecorderDelegate
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    if (flag) {
//        NSLog(@"录音成功");
    }
}

#pragma mark - # Getter
/*
- (AVAudioRecorder *)recorder
{
    if (_recorder == nil) {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        NSError *sessionError;
        [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError];
        
        if(session == nil){
            DDLogError(@"Error creating session: %@", [sessionError description]);
            return nil;
        }
        else {
            [session setActive:YES error:nil];
        }
        
        // 设置录音的一些参数
        NSMutableDictionary *setting = [NSMutableDictionary dictionary];
        setting[AVFormatIDKey] = @(kAudioFormatAppleIMA4);              // 音频格式
        setting[AVSampleRateKey] = @(44100);                            // 录音采样率(Hz)
        setting[AVNumberOfChannelsKey] = @(1);                          // 音频通道数 1 或 2
        setting[AVLinearPCMBitDepthKey] = @(8);                         // 线性音频的位深度
        setting[AVEncoderAudioQualityKey] = [NSNumber numberWithInt:AVAudioQualityHigh];        //录音的质量
        
        _recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.recFilePath] settings:setting error:NULL];
        _recorder.delegate = self;
        _recorder.meteringEnabled = YES;
    }
    return _recorder;
}
*/
//录音设置
- (AVAudioRecorder *)recorder
{
    if (_recorder == nil) {
        //用于获取IOS7的录音权限
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        NSError *sessionError;
        [audioSession setCategory:AVAudioSessionCategoryRecord error:&sessionError];
        if(audioSession == nil){
            DDLogError(@"Error creating session: %@", [sessionError description]);
            return nil;
        }
        else {
            [audioSession setActive:YES error:nil];
        }
        //录音设置
        NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc]init];
        //设置录音格式  AVFormatIDKey==kAudioFormatLinearPCM
        [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
        //设置录音采样率(Hz) 如：AVSampleRateKey==8000/44100/96000（影响音频的质量）
        [recordSetting setValue:[NSNumber numberWithFloat:11025.0] forKey:AVSampleRateKey];
        //录音通道数  1 或 2
        [recordSetting setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
        //线性采样位数  8、16、24、32
        [recordSetting setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
        //录音的质量
        [recordSetting setValue:[NSNumber numberWithInt:AVAudioQualityMin] forKey:AVEncoderAudioQualityKey];
        
        //录音文件的存放
        NSURL *url = [NSURL fileURLWithPath:self.recFilePath];
        
        NSError *error;
        //初始化
        _recorder = [[AVAudioRecorder alloc]initWithURL:url settings:recordSetting error:&error];
        //开启音量检测
        _recorder.meteringEnabled = YES;
        _recorder.delegate = self;
    }
    
    return _recorder;
}
- (NSString *)recFilePath
{
    return PATH_RECFILE;
}

- (NSString *)mp3FilePath
{
    return PATH_MP3FILE;
}

#pragma mark - Private

//转编码为 mp3
- (void)audio_PCMtoMP3:(NSString *)cafFilePath andMP3FilePath:(NSString *)mp3FilePath
{
    NSFileManager* fileManager=[NSFileManager defaultManager];
    if([fileManager removeItemAtPath:mp3FilePath error:nil]) {
        NSLog(@"删除");
    }
    
    @try {
        int read, write;
        
        FILE *pcm = fopen([cafFilePath cStringUsingEncoding:1], "rb");  //source 被转换的音频文件位置
        
        if(pcm == NULL) {
            NSLog(@"file not found");
        } else {
            fseek(pcm, 4*1024, SEEK_CUR);                                   //skip file header
            FILE *mp3 = fopen([mp3FilePath cStringUsingEncoding:1], "wb");  //output 输出生成的Mp3文件位置
            
            const int PCM_SIZE = 8192;
            const int MP3_SIZE = 8192;
            short int pcm_buffer[PCM_SIZE*2];
            unsigned char mp3_buffer[MP3_SIZE];
            
            lame_t lame = lame_init();
            lame_set_in_samplerate(lame, 11025.0);
            lame_set_VBR(lame, vbr_default);
            lame_init_params(lame);
            
            do {
                read = fread(pcm_buffer, 2 * sizeof(short int), PCM_SIZE, pcm);
                if (read == 0)
                    write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
                else
                    write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
                
                fwrite(mp3_buffer, write, 1, mp3);
                
            } while (read != 0);
            
            lame_close(lame);
            fclose(mp3);
            fclose(pcm);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"%@",[exception description]);
    }
    @finally {
        NSLog(@"MP3生成成功");
        if (self.completeBlock) {
            self.completeBlock(PATH_MP3FILE, self.time);
            self.completeBlock = nil;
        }
    }
}

@end
