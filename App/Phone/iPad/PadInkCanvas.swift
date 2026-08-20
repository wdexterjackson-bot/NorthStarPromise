import PencilKit
import SwiftUI

/// PencilKit bridge for the ruled page's ink layer. `isActive` gates
/// `isUserInteractionEnabled` rather than relying solely on the SwiftUI
/// `.allowsHitTesting` the parent already applies, so the underlying
/// `PKCanvasView` never captures touches meant for the text layer beneath
/// it even if hit-testing is ever restructured. `tool` is computed by the
/// parent from the active palette selection + chosen colour (docs/07 §5:
/// pen in black or green, highlighter in yellow).
struct PadInkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool
    var tool: PKTool
    var onDrawingChanged: (PKDrawing) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = tool
        canvasView.drawing = drawing
        canvasView.isUserInteractionEnabled = isActive
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        canvasView.isUserInteractionEnabled = isActive
        canvasView.tool = tool
        if canvasView.drawing != drawing {
            canvasView.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void

        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
