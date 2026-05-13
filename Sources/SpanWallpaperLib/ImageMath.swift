import CoreGraphics

public enum ImageMath {
    public static func sourceFillRect(sourceSize src: CGSize, canvas: CGSize) -> CGRect {
        let srcAspect = src.width / src.height
        let canvasAspect = canvas.width / canvas.height

        if srcAspect > canvasAspect {
            let cropW = src.height * canvasAspect
            return CGRect(x: (src.width - cropW) / 2.0, y: 0,
                          width: cropW, height: src.height)
        } else {
            let cropH = src.width / canvasAspect
            return CGRect(x: 0, y: (src.height - cropH) / 2.0,
                          width: src.width, height: cropH)
        }
    }
}
