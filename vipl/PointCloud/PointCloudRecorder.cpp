// Nuonchic
//
// The MIT License (MIT)
//

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/param.h>

#include <string>
#include <chrono>
#include "PointCloudRecorder.h"

namespace vipl {
namespace pointcloud {

PointCloudRecorder::~PointCloudRecorder(void) {
    if (fd > 0)
        ::close(fd);
    if (depths)
        free(depths);
    if (colors)
        free(colors);
}

// [magic:8][version:4][count:4][start-time:8][end-time:8]
// [size:4][index:4][time:8] [info-size:4][info:<info-size>] [depths-size:4][depths:<depths-size>] [colors-size:4][colors:<depths-size>] [size:4]
int PointCloudRecorder::open(const std::string &fileName, bool forWrite)
{
    if (fd > 0)
        return -1;

    fd = -1;
    this->forWrite = forWrite;
    startTime = endTime = currentTime = 0;
    frameCount = 0;
    frameNumber = -1;
    info.clear();

    if (depths)
        free(depths);
    depths = NULL;
    if (colors)
        free(colors);
    colors = NULL;

    fd = ::open(fileName.c_str(), forWrite ? (O_CREAT | O_RDWR | O_TRUNC) : O_RDONLY, 0666);
    if (fd == -1)
        return -1;

    uint32_t cnt;
    uint32_t ver = htonl(version);
    uint64_t st, et;
    if (forWrite) {
        ver = htonl(version);
        cnt = 0;
        st = *((uint64_t *) &startTime);
        et = *((uint64_t *) &endTime);
        st = htonll(st);
        et = htonll(et);

        if (write(fd, magic, strlen(magic)) != (ssize_t) strlen(magic) ||
            write(fd, &ver, sizeof(ver)) != sizeof(ver) ||
            write(fd, &cnt, sizeof(cnt)) != sizeof(cnt) ||
            write(fd, &st, sizeof(double)) != sizeof(double) ||
            write(fd, &et, sizeof(double)) != sizeof(double))
            return -1;
        return 0;
    } else {
        char tm[32];

        if (read(fd, tm, strlen(magic)) != (ssize_t) strlen(magic) ||
            strncmp(magic, tm, strlen(magic)) != 0 ||
            read(fd, &ver, sizeof(ver)) != sizeof(ver) ||
            read(fd, &cnt, sizeof(cnt)) != sizeof(cnt) ||
            read(fd, &st, sizeof(double)) != sizeof(double) ||
            read(fd, &et, sizeof(double)) != sizeof(double))
            return -1;
        ver = ntohl(ver);
        frameCount = (int) ntohl(cnt);
        st = ntohll(st);
        et = ntohll(et);
        startTime = *((double *) &st);
        endTime = *((double *) &et);
        return first();
    }
}

void PointCloudRecorder::close(void)
{
    if (fd > 0) {
        if (forWrite) {
            uint32_t cnt = htonl(frameCount);
            uint64_t st = *((uint64_t *) &startTime), et = *((uint64_t *) &endTime);
            st = htonll(st); et = htonll(et);

            if (lseek(fd, strlen(magic) + sizeof(version), 0) == -1 ||
                write(fd, &cnt, sizeof(cnt)) != sizeof(cnt) ||
                write(fd, &st, sizeof(double)) != sizeof(double) ||
                write(fd, &et, sizeof(double)) != sizeof(double))
                // TODO: error handling
                ;
        }
        ::close(fd);
    }
    if (depths)
        free(depths);
    if (colors)
        free(colors);

    fd = -1;
    forWrite = false;
    frameCount = 0;
    frameNumber = 0;
    info.clear();
    depths = NULL;
    colors = NULL;
}

// if data == NULL, it's going to be allocated
int PointCloudRecorder::readn(void *&data, int32_t size)
{
    int32_t len;

    if (read(fd, &len, sizeof(len)) != sizeof(len) ||
        (len = ntohl(len)) <= 0)
        return -1;

    if (data == NULL)
        data = (void *) malloc(len);
    else if (size > 0 && len > size)
        return -1;

    if (read(fd, data, len) != (ssize_t) len)
        return -1;
    if (len < size)
        ((char *) data)[len] = 0;

    return 0;
}

int PointCloudRecorder::writen(void *data, int32_t len)
{
    int32_t nlen;

    if (len == 0)
        len = (int32_t) strlen((char *) data);
    nlen = (int32_t) htonl(len);
    if (write(fd, &nlen, sizeof(nlen)) != sizeof(nlen) ||
        write(fd, data, (size_t) len) != (ssize_t) len)
        return -1;
    return (int) len;
}

int PointCloudRecorder::record(double time, const std::string &info, int count,
                               float *depths, uint8_t *colors)
{
    if (!forWrite)
        return -1;

    if (lseek(fd, 0, 2) == -1)
        return -1;

    currentTime = endTime = time;
    if (frameCount == 0)
        startTime = time;
    frameNumber = frameCount;
    frameCount++;
    frameSize = (int) (strlen(info.c_str()) + count * (sizeof(float) + 4 * sizeof(uint8_t)));
    frameSize += 6 * sizeof(int32_t) + sizeof(int64_t);

    int32_t sz  = (int32_t) htonl((int32_t) frameSize);
    int32_t ix  = (int32_t) htonl((int32_t) frameNumber);
    int64_t t = *((uint64_t *) &time);
    t = htonll(t);
    int32_t cnt = (int32_t) htonl((int32_t) frameCount);

    if (write(fd, &sz, sizeof(sz)) != sizeof(sz) ||
        write(fd, &ix, sizeof(ix)) != sizeof(ix) ||
        write(fd, &t, sizeof(t)) != sizeof(t) ||
        writen((void *) info.c_str(), 0) == -1 ||
        writen(depths, count * sizeof(float)) == -1 ||
        writen(colors, count * 4 * sizeof(uint8_t)) == -1 ||
        write(fd, &sz, sizeof(sz)) != sizeof(sz) ||
        lseek(fd, sizeof(uint64_t) + sizeof(uint32_t), 0) == -1 ||
        write(fd, &cnt, sizeof(cnt)) != sizeof(cnt) ||
        lseek(fd, 0, 2) == -1)
        return -1;

    return 0;
}

int PointCloudRecorder::readFrame(bool skip)
{
    int32_t sz, ix;
    int64_t t;
    char info[8192];

    // [frame-size:4] [frame-number:4] [time:8]
    if (read(fd, &sz, sizeof(sz)) != sizeof(sz) ||
        read(fd, &ix, sizeof(ix)) != sizeof(ix) ||
        read(fd, &t, sizeof(t)) != sizeof(t))
        return -1;
    sz = ntohl(sz);
    ix = ntohl(ix);
    t = ntohll(t);

    if (skip) {
        if (lseek(fd, sz - (2 * sizeof(int32_t) + sizeof(double)), 1) == -1)
            return -1;

        currentTime = *((double *) &t);
        frameSize = sz;
        frameNumber = ix;
        return 0;
    }

    // info, depths & colors
    void *ptr;
    if ((ptr = info) == NULL ||
        readn(ptr, sizeof(info)) == -1 ||
        (ptr = depths) == (void *) 0x01 ||
        readn(ptr, 0) == -1 ||
        (depths = (float *) ptr) == NULL ||
        (ptr = colors) == (void *) 0x01 ||
        readn(ptr, 0) == -1 ||
        (colors = (uint8_t *) ptr) == NULL)
        return -1;

    // size again
    if (read(fd, &sz, sizeof(sz)) != sizeof(sz))
        return -1;
    sz = ntohl(sz);

    currentTime = *((double *) &t);
    frameNumber = ix;
    frameSize = sz;
    this->info = info;

    return 0;
}

int PointCloudRecorder::prevFrame(bool skip)
{
    int32_t sz;

    // skipping two frames
    if (lseek(fd, -sizeof(int32_t), 1) == -1 ||
        read(fd, &sz, sizeof(sz)) != sizeof(sz) ||
        (sz = ntohl(sz)) == 0 ||
        lseek(fd, -sz, 1) == -1 ||
        lseek(fd, -sizeof(int32_t), 1) == -1 ||
        read(fd, &sz, sizeof(sz)) != sizeof(sz) ||
        (sz = ntohl(sz)) == 0 ||
        lseek(fd, -sz, 1) == -1)
        return -1;
    return readFrame(skip);
}

int PointCloudRecorder::nextFrame(bool skip)
{
    return readFrame(skip);
}

int PointCloudRecorder::seek(int count, int whence)
{
    int off;

    switch (whence) {
        case 0:
            off = count;
            break;
        case 1:
            off = frameNumber + count;
            break;
        case 2:
            off = frameCount + count;
            break;
        default:
            return -1;
    }

    if (off < 0)
        off = 0;
    else if (off >= frameCount)
        off = frameCount - 1;

    int off1 = off, off2 = abs(frameNumber - off), off3 = frameCount - off;
    if (off == frameNumber)
        ;
    else if (off1 < off2 && off1 <= off3) {
        // from the beginning
        if (lseek(fd, sizeof(uint64_t) + sizeof(uint32_t) + sizeof(int32_t) + 2 * sizeof(double), 0) == -1)
            return -1;
        while (off1-- >= 0) {
            if (nextFrame(off1 == -1 ? false : true) == -1)
                return -1;
        }
    } else if (off3 <= off1 && off3 < off2) {
        // from the end
        if (lseek(fd, 0, 2) == -1)
            return -1;
        while (off3-- > 0) {
            if (prevFrame(off3 == 0 ? false : true) == -1)
                return -1;
        }
    } else {
        // from the current location
        while (off2-- > 0) {
            if (off < frameNumber &&
                prevFrame(off2 == 0 ? false : true) == -1)
                return -1;
            if (off > frameNumber &&
                nextFrame(off2 == 0 ? false : true) == -1)
                return -1;
        }
    }

    return 0;
}

} // namespace pointcloud
} // namespace vipl

// EOF
