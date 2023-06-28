//
//  ThumbnailCache.swift
//  vipl
//
//  Created by Steve H. Jung on 6/27/23.
//

import UIKit
import AVFoundation

class ThumbnailCacheItem {
    let image: UIImage
    let fileSize: UInt64
    let modifiedTime: Date

    init(image: UIImage, fileSize: UInt64, modifiedTime: Date) {
        self.image = image
        self.fileSize = fileSize
        self.modifiedTime = modifiedTime
    }
}

class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, ThumbnailCacheItem>()

    func setThumbnail(_ thumbnail: UIImage, for url: URL, fileSize: UInt64, modifiedTime: Date) {
        let cacheItem = ThumbnailCacheItem(image: thumbnail, fileSize: fileSize, modifiedTime: modifiedTime)
        cache.setObject(cacheItem, forKey: url as NSURL)
    }

    func getThumbnail(for url: URL) -> UIImage? {
        let fileAttributes: [FileAttributeKey: Any]
        do {
            fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            print("Error fetching file attributes: \(error)")
            return nil
        }

        guard let fileSize = fileAttributes[.size] as? UInt64,
              let modifiedTime = fileAttributes[.modificationDate] as? Date else {
            return nil
        }

        if let cacheItem = cache.object(forKey: url as NSURL) {
            if cacheItem.fileSize == fileSize && cacheItem.modifiedTime == modifiedTime {
                return cacheItem.image
            }
        }

        // The cache is not valid, generate a new thumbnail and update the cache
        guard let newThumbnail = generateThumbnail(from: url) else {
            return nil
        }
        setThumbnail(newThumbnail, for: url, fileSize: fileSize, modifiedTime: modifiedTime)
        return newThumbnail
    }

    private func generateThumbnail(from url: URL, size: Int = 480) -> UIImage? {
        func newSize(width: Int, height: Int) -> CGSize {
            if width <= size && height <= size {
                return CGSize(width: width, height: height)
            } else if width >= height {
                return CGSize(width: size, height: size * height / width)
            } else {
                return CGSize(width: size * width / height, height: size)
            }
        }

        if url.pathExtension != "moz" {
            let asset = AVAsset(url: url)
            let assetImgGenerate = AVAssetImageGenerator(asset: asset)
            assetImgGenerate.appliesPreferredTrackTransform = true
            let pointOfTime = CMTimeMakeWithSeconds(0.1, preferredTimescale: 600)
            do {
                let img = try assetImgGenerate.copyCGImage(at: pointOfTime, actualTime: nil)
                return UIImage(cgImage: img).resized(to: newSize(width: img.width, height: img.height))
            } catch {
                print("\(error.localizedDescription)")
                return nil
            }
        } else {
            let r = PointCloudRecorder()
            if !r.open(url.path, forWrite: false) {
                return nil
            }
            if let info = r.info(),
               let calibrationInfo = FrameCalibrationInfo.fromJson(data: info),
               let colors = r.colors(),
               let cgImg = PointCloud2.bytesToImage(width: calibrationInfo.width, height: calibrationInfo.height, colors: colors) {
                return UIImage(cgImage: cgImg).resized(to: newSize(width: cgImg.width, height: cgImg.height))
            }
            return nil
        }
    }
}
