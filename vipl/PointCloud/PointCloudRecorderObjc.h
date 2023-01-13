//
//  PointCloudRecorderObjc.h
//  vipl
//
//  Created by Steve H. Jung on 1/11/23.
//

#ifndef PointCloudRecorderObjc_h
#define PointCloudRecorderObjc_h

@interface PointCloudRecorder : NSObject
+ (bool)isMovieFile:(NSString *)fileName;

- (void)lock;
- (void)unlock;

- (bool)forWrite;
- (double)startTime;
- (double)endTime;
- (double)currentTime;
- (int)frameNumber;
- (int)frameCount;
- (int)frameSize;
- (NSString *)info;
- (Float32 *)depths;
- (unsigned char *)colors;

- (double)recordedDuration;

- (bool)open:(NSString *)fileName forWrite:(bool)forWrite;
- (void)close;

// record
- (int)record:(double)time info:(NSString *)info count:(int)count depths:(float *)depths colors:(unsigned char *)colors;

- (int)seek:(int)count whence:(int)whence;
- (int)next:(int)count;
- (int)next;
- (int)prev:(int)count;
- (int)prev;
- (int)first;
- (int)last;

- (int)readFrame:(bool)skip;
- (int)nextFrame:(bool)skip;
- (int)prevFrame:(bool)skip;

@end

#endif /* PointCloudRecorderObjc_h */
