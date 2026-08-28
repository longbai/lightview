#ifndef LIGHTVIEW_SVG_ADAPTER_H
#define LIGHTVIEW_SVG_ADAPTER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LVSVGDocument LVSVGDocument;
typedef struct LVSVGShape LVSVGShape;
typedef struct LVSVGPath LVSVGPath;

enum {
    LVSVGPaintNone = 0,
    LVSVGPaintColor = 1,
    LVSVGPaintLinearGradient = 2,
    LVSVGPaintRadialGradient = 3
};

LVSVGDocument *LVSVGDocumentCreate(const uint8_t *bytes, size_t length);
void LVSVGDocumentDestroy(LVSVGDocument *document);
float LVSVGDocumentWidth(const LVSVGDocument *document);
float LVSVGDocumentHeight(const LVSVGDocument *document);

const LVSVGShape *LVSVGDocumentFirstShape(const LVSVGDocument *document);
const LVSVGShape *LVSVGShapeNext(const LVSVGShape *shape);
int LVSVGShapeIsVisible(const LVSVGShape *shape);
float LVSVGShapeOpacity(const LVSVGShape *shape);
int LVSVGShapeFillRule(const LVSVGShape *shape);
int LVSVGShapeFillType(const LVSVGShape *shape);
int LVSVGShapeStrokeType(const LVSVGShape *shape);
uint32_t LVSVGShapeFillColor(const LVSVGShape *shape);
uint32_t LVSVGShapeStrokeColor(const LVSVGShape *shape);
float LVSVGShapeStrokeWidth(const LVSVGShape *shape);
float LVSVGShapeMiterLimit(const LVSVGShape *shape);
int LVSVGShapeLineCap(const LVSVGShape *shape);
int LVSVGShapeLineJoin(const LVSVGShape *shape);
int LVSVGShapeDashCount(const LVSVGShape *shape);
float LVSVGShapeDashValue(const LVSVGShape *shape, int index);
float LVSVGShapeDashOffset(const LVSVGShape *shape);

int LVSVGShapeGradientStopCount(const LVSVGShape *shape, int stroke);
uint32_t LVSVGShapeGradientStopColor(const LVSVGShape *shape, int stroke, int index);
float LVSVGShapeGradientStopOffset(const LVSVGShape *shape, int stroke, int index);
float LVSVGShapeGradientTransform(const LVSVGShape *shape, int stroke, int index);

const LVSVGPath *LVSVGShapeFirstPath(const LVSVGShape *shape);
const LVSVGPath *LVSVGPathNext(const LVSVGPath *path);
int LVSVGPathPointCount(const LVSVGPath *path);
int LVSVGPathPoint(const LVSVGPath *path, int index, float *x, float *y);
int LVSVGPathIsClosed(const LVSVGPath *path);

#ifdef __cplusplus
}
#endif

#endif
