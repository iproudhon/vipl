//
//  FileSystemHelper.swift
//  vipl
//
//  Created by Steve H. Jung on 1/12/23.
//

import Foundation

class FileSystemHelper {
    public static var swingNumber: String = "swing-number"
    public static var swingFileBaseName: String = "swing-"
    public static var temporaryFileName: String = "tmp-%d.tmp"
    public static var moz: String = "moz"
    public static var mov: String = "mov"

    // returns creationDate, modificationDate
    public static func fileTimes(url: URL) -> (Date?, Date?) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) as [FileAttributeKey:Any],
           let creationDate = attrs[.creationDate] as? Date,
           let modificationDate = attrs[.modificationDate] as? Date {
            return (creationDate, modificationDate)
        } else {
            return (nil, nil)
        }
    }

    public static func isFileInAppDirectory(url: URL) -> Bool {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.deletingLastPathComponent().path == dir.path
    }

    public static func getNextFileName(ext: String = FileSystemHelper.mov) -> URL? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var num = UserDefaults.standard.integer(forKey: FileSystemHelper.swingNumber)
        if num == 0 {
            num = 1
        }
        let moz = FileSystemHelper.moz, MOZ = moz.uppercased(), mov = FileSystemHelper.mov, MOV = mov.uppercased()
        while true {
            let baseName = dir.appendingPathComponent("\(FileSystemHelper.swingFileBaseName)\(String(format: "%04d", num))")
            if FileManager.default.fileExists(atPath: baseName.appendingPathExtension(mov).path) || FileManager.default.fileExists(atPath: baseName.appendingPathExtension(MOV).path) || FileManager.default.fileExists(atPath: baseName.appendingPathExtension(moz).path) ||
                FileManager.default.fileExists(atPath: baseName.appendingPathExtension(MOZ).path) {
                num += 1
                continue
            }
            let url = baseName.appendingPathExtension(ext)
            UserDefaults.standard.set(num + 1, forKey: FileSystemHelper.swingNumber)
            return url
        }
    }

    public static func getTemporaryFileNames() -> (URL?, URL?) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let a = dir.appendingPathComponent(String(format: FileSystemHelper.temporaryFileName, 0))
        let b = dir.appendingPathComponent(String(format: FileSystemHelper.temporaryFileName, 1))
        return (a, b)
    }

    public static func getPrimaryTemporaryFileName() -> URL? {
        let (a, _) = FileSystemHelper.getTemporaryFileNames()
        return a
    }
    public static func getSecondaryTemporaryFileName() -> URL? {
        let (_, b) = FileSystemHelper.getTemporaryFileNames()
        return b
    }
}
