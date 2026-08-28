#include "LightViewSVGAdapter.h"

#include <stdlib.h>
#include <string.h>

#define NANOSVG_IMPLEMENTATION
#include "upstream/src/nanosvg.h"

struct LVSVGDocument {
    NSVGimage *image;
};

static const NSVGshape *LVShape(const LVSVGShape *shape) {
    return (const NSVGshape *)shape;
}

static const NSVGpath *LVPath(const LVSVGPath *path) {
    return (const NSVGpath *)path;
}

static const NSVGpaint *LVPaint(const LVSVGShape *shape, int stroke) {
    const NSVGshape *value = LVShape(shape);
    if (value == NULL) return NULL;
    return stroke ? &value->stroke : &value->fill;
}

LVSVGDocument *LVSVGDocumentCreate(const uint8_t *bytes, size_t length) {
    if (bytes == NULL || length == 0 || length == SIZE_MAX) return NULL;
    char *source = (char *)malloc(length + 1);
    if (source == NULL) return NULL;
    memcpy(source, bytes, length);
    source[length] = '\0';
    NSVGimage *image = nsvgParse(source, "px", 96.0f);
    free(source);
    if (image == NULL) return NULL;
    LVSVGDocument *document = (LVSVGDocument *)malloc(sizeof(LVSVGDocument));
    if (document == NULL) {
        nsvgDelete(image);
        return NULL;
    }
    document->image = image;
    return document;
}

void LVSVGDocumentDestroy(LVSVGDocument *document) {
    if (document == NULL) return;
    nsvgDelete(document->image);
    free(document);
}

float LVSVGDocumentWidth(const LVSVGDocument *document) {
    return document != NULL && document->image != NULL ? document->image->width : 0.0f;
}

float LVSVGDocumentHeight(const LVSVGDocument *document) {
    return document != NULL && document->image != NULL ? document->image->height : 0.0f;
}

const LVSVGShape *LVSVGDocumentFirstShape(const LVSVGDocument *document) {
    if (document == NULL || document->image == NULL) return NULL;
    return (const LVSVGShape *)document->image->shapes;
}

const LVSVGShape *LVSVGShapeNext(const LVSVGShape *shape) {
    return shape == NULL ? NULL : (const LVSVGShape *)LVShape(shape)->next;
}

int LVSVGShapeIsVisible(const LVSVGShape *shape) {
    return shape != NULL && (LVShape(shape)->flags & NSVG_FLAGS_VISIBLE) != 0;
}

float LVSVGShapeOpacity(const LVSVGShape *shape) {
    return shape == NULL ? 0.0f : LVShape(shape)->opacity;
}

int LVSVGShapeFillRule(const LVSVGShape *shape) {
    return shape == NULL ? NSVG_FILLRULE_NONZERO : LVShape(shape)->fillRule;
}

int LVSVGShapeFillType(const LVSVGShape *shape) {
    const NSVGpaint *paint = LVPaint(shape, 0);
    return paint == NULL ? NSVG_PAINT_NONE : paint->type;
}

int LVSVGShapeStrokeType(const LVSVGShape *shape) {
    const NSVGpaint *paint = LVPaint(shape, 1);
    return paint == NULL ? NSVG_PAINT_NONE : paint->type;
}

uint32_t LVSVGShapeFillColor(const LVSVGShape *shape) {
    const NSVGpaint *paint = LVPaint(shape, 0);
    return paint != NULL && paint->type == NSVG_PAINT_COLOR ? paint->color : 0;
}

uint32_t LVSVGShapeStrokeColor(const LVSVGShape *shape) {
    const NSVGpaint *paint = LVPaint(shape, 1);
    return paint != NULL && paint->type == NSVG_PAINT_COLOR ? paint->color : 0;
}

float LVSVGShapeStrokeWidth(const LVSVGShape *shape) {
    return shape == NULL ? 0.0f : LVShape(shape)->strokeWidth;
}

float LVSVGShapeMiterLimit(const LVSVGShape *shape) {
    return shape == NULL ? 4.0f : LVShape(shape)->miterLimit;
}

int LVSVGShapeLineCap(const LVSVGShape *shape) {
    return shape == NULL ? NSVG_CAP_BUTT : LVShape(shape)->strokeLineCap;
}

int LVSVGShapeLineJoin(const LVSVGShape *shape) {
    return shape == NULL ? NSVG_JOIN_MITER : LVShape(shape)->strokeLineJoin;
}

int LVSVGShapeDashCount(const LVSVGShape *shape) {
    return shape == NULL ? 0 : LVShape(shape)->strokeDashCount;
}

float LVSVGShapeDashValue(const LVSVGShape *shape, int index) {
    if (shape == NULL || index < 0 || index >= LVShape(shape)->strokeDashCount || index >= 8) return 0.0f;
    return LVShape(shape)->strokeDashArray[index];
}

float LVSVGShapeDashOffset(const LVSVGShape *shape) {
    return shape == NULL ? 0.0f : LVShape(shape)->strokeDashOffset;
}

int LVSVGShapeGradientStopCount(const LVSVGShape *shape, int stroke) {
    const NSVGpaint *paint = LVPaint(shape, stroke);
    return paint != NULL && paint->gradient != NULL ? paint->gradient->nstops : 0;
}

uint32_t LVSVGShapeGradientStopColor(const LVSVGShape *shape, int stroke, int index) {
    const NSVGpaint *paint = LVPaint(shape, stroke);
    if (paint == NULL || paint->gradient == NULL || index < 0 || index >= paint->gradient->nstops) return 0;
    return paint->gradient->stops[index].color;
}

float LVSVGShapeGradientStopOffset(const LVSVGShape *shape, int stroke, int index) {
    const NSVGpaint *paint = LVPaint(shape, stroke);
    if (paint == NULL || paint->gradient == NULL || index < 0 || index >= paint->gradient->nstops) return 0.0f;
    return paint->gradient->stops[index].offset;
}

float LVSVGShapeGradientTransform(const LVSVGShape *shape, int stroke, int index) {
    const NSVGpaint *paint = LVPaint(shape, stroke);
    if (paint == NULL || paint->gradient == NULL || index < 0 || index >= 6) return 0.0f;
    return paint->gradient->xform[index];
}

const LVSVGPath *LVSVGShapeFirstPath(const LVSVGShape *shape) {
    return shape == NULL ? NULL : (const LVSVGPath *)LVShape(shape)->paths;
}

const LVSVGPath *LVSVGPathNext(const LVSVGPath *path) {
    return path == NULL ? NULL : (const LVSVGPath *)LVPath(path)->next;
}

int LVSVGPathPointCount(const LVSVGPath *path) {
    return path == NULL ? 0 : LVPath(path)->npts;
}

int LVSVGPathPoint(const LVSVGPath *path, int index, float *x, float *y) {
    const NSVGpath *value = LVPath(path);
    if (value == NULL || x == NULL || y == NULL || index < 0 || index >= value->npts) return 0;
    *x = value->pts[index * 2];
    *y = value->pts[index * 2 + 1];
    return 1;
}

int LVSVGPathIsClosed(const LVSVGPath *path) {
    return path != NULL && LVPath(path)->closed != 0;
}
