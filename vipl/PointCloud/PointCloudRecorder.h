// Nuonchic
//
// The MIT License (MIT)
//

#pragma once

namespace vipl {
namespace pointcloud {

class PointCloudRecorder {
public:
    ~PointCloudRecorder(void);

    int open(const std::string &fileName, bool forWrite = false);
    void close(void);

    int record(double time, const std::string &info, int count,
               float *depths, uint8_t *colors);

    int seek(int count, int whence);

    inline int next(int count = 1) { return seek(1, 1); }
    int prev(int count = 1) { return seek(-1, 1); }
    int first(void) { return seek(0, 0); }
    int last(void) { return seek(0, 2); }

    int readFrame(bool skip);
    int nextFrame(bool skip);
    int prevFrame(bool skip);

public:
    const char *magic = "PointCld";
    const uint32_t version = 0x01;
    int fd = -1;

    bool forWrite = false;
    double startTime = 0;
    double endTime = 0;
    double currentTime = 0;
    int frameNumber = 0;
    int frameCount = 0;
    int frameSize = 0;
    std::string info;
    float *depths = NULL;
    uint8_t *colors = NULL;

private:
    int readn(void *&data, int32_t size);
    int writen(void *data, int32_t len);
};

} // namespace pointcloud
} // namespace vipl

// EOF
