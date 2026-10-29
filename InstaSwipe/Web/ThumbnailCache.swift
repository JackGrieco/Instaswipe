import Foundation
import OSLog
import UIKit

actor ThumbnailCache {
    private static let maxSide: CGFloat = 200
    private static let jpegQuality: CGFloat = 0.8
    private static let logger = Logger(subsystem: "com.giacomogrieco.InstaSwipe", category: "ThumbnailCache")

    private let directory: URL

    init(directory: URL = ThumbnailCache.defaultDirectory) {
        self.directory = directory
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
    }

    func image(for username: String) -> UIImage? {
        UIImage(contentsOfFile: fileURL(for: username).path)
    }

    /// Downloads, resizes and stores the thumbnail. Failures are logged, never thrown.
    func store(from url: URL, username: String) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let source = UIImage(data: data) else {
                Self.logger.error("Undecodable thumbnail for \(username, privacy: .private)")
                return
            }
            guard let jpeg = Self.resized(source).jpegData(compressionQuality: Self.jpegQuality) else {
                Self.logger.error("JPEG encoding failed for \(username, privacy: .private)")
                return
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: fileURL(for: username), options: .atomic)
        } catch {
            Self.logger.error("Thumbnail store failed: \(error.localizedDescription)")
        }
    }

    private func fileURL(for username: String) -> URL {
        directory.appendingPathComponent("\(username).jpg")
    }

    private static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
