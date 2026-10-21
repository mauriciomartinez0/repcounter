// The exercise demonstration. Most exercises have two photos from
// free-exercise-db (start and end position, public domain) that alternate
// with a crossfade; the rest fall back to the 180 × 180 animation from the
// exercises dataset (media © Gym visual — https://gymvisual.com/).

import ImageIO
import SwiftUI
import UIKit

/// Start and end photos, by exercise id.
@MainActor
enum ExercisePhotos {
    private static let cache = NSCache<NSString, NSArray>()

    static func photos(for exerciseId: String) -> [UIImage]? {
        if let cached = cache.object(forKey: exerciseId as NSString) as? [UIImage] { return cached }
        let images = (0...1).compactMap { i -> UIImage? in
            guard let url = Bundle.module.url(forResource: "\(exerciseId)-\(i)", withExtension: "jpg",
                                              subdirectory: "ExercisePhotos")
            else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        guard images.count == 2 else { return nil }
        cache.setObject(images as NSArray, forKey: exerciseId as NSString)
        return images
    }
}

/// Whatever demonstration the exercise has: photos, else the animation.
struct ExerciseDemoView: View {
    let exercise: Exercise

    static func available(_ exercise: Exercise) -> Bool {
        ExercisePhotos.photos(for: exercise.id) != nil || ExerciseAnimations.hasAnimation(exercise.id)
    }

    var body: some View {
        if let photos = ExercisePhotos.photos(for: exercise.id) {
            PhotoDemoView(exercise: exercise, photos: photos)
        } else {
            ExerciseAnimationView(exercise: exercise)
        }
    }
}

/// Start and end position alternating, so the photos read as the movement.
/// Tapping pauses on the photo that is showing.
private struct PhotoDemoView: View {
    let exercise: Exercise
    let photos: [UIImage]
    @Environment(\.colors) private var c
    @State private var index = 0
    @State private var playing = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Pressable(action: { playing.toggle() },
                      label: playing ? "Pausar demostración" : "Reproducir demostración") {
                ZStack {
                    ForEach(0..<photos.count, id: \.self) { i in
                        Image(uiImage: photos[i])
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .opacity(i == index ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 2, contentMode: .fit)
                .background(Color.black, in: RoundedRectangle(cornerRadius: kRadius))
                .clipShape(RoundedRectangle(cornerRadius: kRadius))
                .overlay(alignment: .bottomLeading) {
                    Text(index == 0 ? "INICIO" : "FINAL")
                        .font(.text(11, .semibold))
                        .tracking(1.1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .padding(8)
                }
                .overlay {
                    if !playing {
                        AppIcon(.play, size: 24, color: c.btnInk, strokeWidth: 2)
                            .frame(width: 64, height: 64)
                            .background(c.btnBg, in: Circle())
                    }
                }
            }
            .accessibilityHint("Posición inicial y final de \(exercise.name)")
            Text("Fotos: free-exercise-db (dominio público)")
                .font(.text(12))
                .foregroundStyle(c.ink3)
        }
        .task(id: playing) {
            // Hold each position long enough to read it, then crossfade.
            while playing && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1400))
                guard playing, !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) { index = (index + 1) % photos.count }
            }
        }
    }
}

/// Decoded animations, by exercise id.
@MainActor
enum ExerciseAnimations {
    private static let cache = NSCache<NSString, UIImage>()

    static func hasAnimation(_ exerciseId: String) -> Bool { url(exerciseId) != nil }

    private static func url(_ exerciseId: String) -> URL? {
        Bundle.module.url(forResource: exerciseId, withExtension: "gif", subdirectory: "ExerciseAnimations")
    }

    static func animation(for exerciseId: String) -> UIImage? {
        if let cached = cache.object(forKey: exerciseId as NSString) { return cached }
        guard let url = url(exerciseId),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        // UIImage animations show every frame for the same time, while a GIF
        // gives each frame its own delay. Frames are repeated in proportion
        // to their delay, in steps of the shortest one.
        var frames: [(CGImage, Double)] = []
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append((image, delay(source, i)))
        }
        guard let unit = frames.map(\.1).min(), unit > 0 else { return nil }
        var sequence: [UIImage] = []
        for (image, delay) in frames {
            let repeats = max(1, Int((delay / unit).rounded()))
            let frame = UIImage(cgImage: image)
            sequence.append(contentsOf: Array(repeating: frame, count: repeats))
        }
        let total = frames.reduce(0) { $0 + $1.1 }
        guard let animated = UIImage.animatedImage(with: sequence, duration: total) else { return nil }
        cache.setObject(animated, forKey: exerciseId as NSString)
        return animated
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        // Browsers treat very short delays as 0.1 s; so does this.
        return value < 0.02 ? 0.1 : value
    }
}

/// Plays the animation in a loop. Tapping it pauses and resumes.
struct ExerciseAnimationView: View {
    let exercise: Exercise
    @Environment(\.colors) private var c
    @State private var playing = true

    var body: some View {
        if let animation = ExerciseAnimations.animation(for: exercise.id) {
            VStack(alignment: .leading, spacing: 8) {
                Pressable(action: { playing.toggle() },
                          label: playing ? "Pausar animación" : "Reproducir animación") {
                    AnimatedImage(image: animation, playing: playing)
                        .aspectRatio(1, contentMode: .fit)
                        // The source is 180 px; past this size it only gets
                        // blurrier.
                        .frame(maxWidth: 200)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        // The drawings have a white background in both themes.
                        .background(Color.white, in: RoundedRectangle(cornerRadius: kRadius))
                        .overlay(RoundedRectangle(cornerRadius: kRadius).strokeBorder(c.line, lineWidth: 1))
                        .overlay {
                            if !playing {
                                AppIcon(.play, size: 24, color: c.btnInk, strokeWidth: 2)
                                    .frame(width: 64, height: 64)
                                    .background(c.btnBg, in: Circle())
                            }
                        }
                }
                .accessibilityHint("Animación de \(exercise.name)")
                // Required by the media license.
                Text("Animación © Gym visual — gymvisual.com")
                    .font(.text(12))
                    .foregroundStyle(c.ink3)
            }
        }
    }
}

private struct AnimatedImage: UIViewRepresentable {
    let image: UIImage
    let playing: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.animationImages?.first !== image.images?.first {
            view.animationImages = image.images
            view.animationDuration = image.duration
            view.image = image.images?.first
        }
        if playing {
            if !view.isAnimating { view.startAnimating() }
        } else if view.isAnimating {
            // Freeze on the frame that is showing instead of jumping back to
            // the first one.
            let showing = view.layer.presentation()?.contents
            view.stopAnimating()
            if let showing, CFGetTypeID(showing as CFTypeRef) == CGImage.typeID {
                view.image = UIImage(cgImage: showing as! CGImage)
            }
        }
    }
}
