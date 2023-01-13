//
//  PointCloudRecorderObjc.m
//  vipl
//
//  Created by Steve H. Jung on 1/11/23.
//

#import <Foundation/Foundation.h>
#import <mutex>

#import "PointCloudRecorderObjc.h"
#import "PointCloudRecorder.h"

using namespace std;
using namespace vipl;

// PointCloudRecorder
@interface PointCloudRecorder () {
    vipl::pointcloud::PointCloudRecorder recorder;
    std::recursive_mutex lck;
    bool inRecording;
}
@end

// NSString * <-> std::string
NSString *str2ns(const std::string &s) {
    return [NSString stringWithCString:s.c_str() encoding:[NSString defaultCStringEncoding]];
}

std::string ns2str(NSString *ns) {
    return std::string([ns UTF8String]);
}

@implementation PointCloudRecorder
- (void)lock { lck.lock(); }
- (void)unlock { lck.unlock(); }

- (bool)forWrite { return recorder.forWrite; }
- (double)startTime { return recorder.startTime; }
- (double)endTime { return recorder.endTime; }
- (double)currentTime { return recorder.currentTime; }
- (int)frameNumber { return recorder.frameNumber; }
- (int)frameCount { return recorder.frameCount; }
- (int)frameSize { return recorder.frameCount; }
- (NSString *)info { @synchronized (self) { return str2ns(recorder.info); } }
- (Float32 *)depths { return recorder.depths; }
- (unsigned char *)colors { return recorder.colors; }

- (double)recordedDuration { return recorder.endTime - recorder.startTime; }


// [magic:8][version:4][count:4][start-time:8][end-time:8]
// [size:4][index:4][time:8] [info-size:4][info:<info-size>] [depths-size:4][depths:<depths-size>] [colors-size:4][colors:<depths-size>] [size:4]
- (bool)open:(NSString *)fileName forWrite:(bool)forWrite {
    std::unique_lock<std::recursive_mutex> lk(lck);
    if (forWrite)
        inRecording = true;
    return recorder.open(ns2str(fileName), forWrite) != -1;
}

- (void)close {
    std::unique_lock<std::recursive_mutex> lk(lck);
    inRecording = false;
    recorder.close();
}

- (int)record:(double)time info:(NSString *)info count:(int)count depths:(Float32 *)depths colors:(unsigned char *)colors {
    std::unique_lock<std::recursive_mutex> lk(lck);
    // TODO: remove this line
    if (recorder.frameCount > 500)
        return -1;
    if (!inRecording)
        return -1;
    return recorder.record(time, ns2str(info), count, depths, colors);
}

- (int)seek:(int)count whence:(int)whence {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.seek(count, whence);
}

- (int)next:(int)count {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.next(count);
}

- (int)next {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.next(1);
}

- (int)prev:(int)count {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.prev(count);
}

- (int)prev {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.prev(1);
}

- (int)first {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.first();
}

- (int)last {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.last();
}

- (int)readFrame:(bool)skip {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.readFrame(skip);
}

- (int)nextFrame:(bool)skip {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.nextFrame(skip);
}

- (int)prevFrame:(bool)skip {
    std::unique_lock<std::recursive_mutex> lk(lck);
    return recorder.prevFrame(skip);
}

+ (bool)isMovieFile:(NSString *)fileName {
    vipl::pointcloud::PointCloudRecorder r;
    int v = r.open(ns2str(fileName));
    if (v != -1)
        r.close();
    return v != -1;
}

@end
