import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart helpers for EfficientDet-Lite0 (320x320, 90 COCO classes):
/// anchor generation, box decoding, NMS and a small centroid tracker.
/// Kept free of plugins so it can be unit tested without a device.

const int inputSize = 320;
const int numClasses = 90;

/// COCO 90-class ids (1-based) we treat as livestock: bird, horse, sheep, cow.
const Set<int> livestockClassIds = {16, 19, 20, 21};

class Detection {
  Detection(this.cx, this.cy, this.w, this.h, this.score);
  final double cx, cy, w, h, score;

  double get left => cx - w / 2;
  double get right => cx + w / 2;
  double get top => cy - h / 2;
  double get bottom => cy + h / 2;
}

/// Anchors as a flat list of [yc, xc, h, w] in 320x320 pixels. Order matches
/// the model output: level (stride 8..128), then y, x, then 3 scales x 3 ratios.
Float32List buildAnchors() {
  final out = <double>[];
  const strides = [8, 16, 32, 64, 128];
  const ratios = [(1.0, 1.0), (1.4, 0.7), (0.7, 1.4)];
  for (final stride in strides) {
    final n = (inputSize / stride).ceil();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        for (var s = 0; s < 3; s++) {
          final scale = math.pow(2.0, s / 3.0).toDouble();
          for (final r in ratios) {
            final sx = 4 * stride * scale * r.$1;
            final sy = 4 * stride * scale * r.$2;
            out.addAll([(y + 0.5) * stride, (x + 0.5) * stride, sy, sx]);
          }
        }
      }
    }
  }
  return Float32List.fromList(out);
}

/// Decode raw model outputs into candidate detections in original-image
/// pixels. [boxes] is N*4 ([ty, tx, th, tw]), [scores] is N*90. [scale] is the
/// letterbox factor (320 / longer side of the original image).
List<Detection> decode(
  Float32List boxes,
  Float32List scores,
  Float32List anchors, {
  required double scale,
  double threshold = 0.3,
  Set<int> classIds = livestockClassIds,
}) {
  final n = anchors.length ~/ 4;
  final result = <Detection>[];
  for (var i = 0; i < n; i++) {
    var best = 0.0;
    for (final id in classIds) {
      final s = scores[i * numClasses + (id - 1)];
      if (s > best) best = s;
    }
    if (best < threshold) continue;
    final ya = anchors[i * 4], xa = anchors[i * 4 + 1];
    final ha = anchors[i * 4 + 2], wa = anchors[i * 4 + 3];
    final cy = boxes[i * 4] * ha + ya;
    final cx = boxes[i * 4 + 1] * wa + xa;
    final h = math.exp(boxes[i * 4 + 2]) * ha;
    final w = math.exp(boxes[i * 4 + 3]) * wa;
    result.add(Detection(cx / scale, cy / scale, w / scale, h / scale, best));
  }
  return result;
}

double iou(Detection a, Detection b) {
  final iw = math.min(a.right, b.right) - math.max(a.left, b.left);
  final ih = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (iw <= 0 || ih <= 0) return 0;
  final inter = iw * ih;
  return inter / (a.w * a.h + b.w * b.h - inter);
}

List<Detection> nms(List<Detection> dets, {double iouThreshold = 0.5}) {
  final sorted = [...dets]..sort((a, b) => b.score.compareTo(a.score));
  final kept = <Detection>[];
  for (final d in sorted) {
    if (kept.every((k) => iou(k, d) < iouThreshold)) kept.add(d);
  }
  return kept;
}

class _Track {
  _Track(this.id, this.cx, this.cy, this.size);
  final int id;
  double cx, cy, size;
  double vx = 0, vy = 0; // smoothed motion per frame
  int missed = 0;
}

/// Greedy nearest-centroid tracker. A detection is matched to the closest
/// track within [maxDistFactor] x the larger box side; tracks are dropped
/// after [maxMissed] frames without a match.
class CentroidTracker {
  CentroidTracker({this.maxDistFactor = 0.8, this.maxMissed = 5});

  final double maxDistFactor;
  final int maxMissed;
  final List<_Track> _tracks = [];
  int _nextId = 1;

  /// Returns track id -> (cx, cy) for the current frame.
  Map<int, (double, double)> update(List<Detection> dets) {
    final pairs = <(double, int, int)>[];
    for (var t = 0; t < _tracks.length; t++) {
      for (var d = 0; d < dets.length; d++) {
        // Compare against where the track should be now, so fast animals
        // that jump between frames keep their id.
        final steps = _tracks[t].missed + 1;
        final px = _tracks[t].cx + _tracks[t].vx * steps;
        final py = _tracks[t].cy + _tracks[t].vy * steps;
        final dist = math.sqrt(
            math.pow(px - dets[d].cx, 2) + math.pow(py - dets[d].cy, 2));
        final limit =
            maxDistFactor * math.max(dets[d].w, dets[d].h).clamp(1, 1e9);
        if (dist <= limit) pairs.add((dist, t, d));
      }
    }
    pairs.sort((a, b) => a.$1.compareTo(b.$1));
    final usedT = <int>{}, usedD = <int>{};
    final out = <int, (double, double)>{};
    for (final p in pairs) {
      if (usedT.contains(p.$2) || usedD.contains(p.$3)) continue;
      usedT.add(p.$2);
      usedD.add(p.$3);
      final tr = _tracks[p.$2];
      final d = dets[p.$3];
      final steps = tr.missed + 1;
      tr.vx = 0.5 * tr.vx + 0.5 * (d.cx - tr.cx) / steps;
      tr.vy = 0.5 * tr.vy + 0.5 * (d.cy - tr.cy) / steps;
      tr
        ..cx = d.cx
        ..cy = d.cy
        ..size = math.max(d.w, d.h)
        ..missed = 0;
      out[tr.id] = (d.cx, d.cy);
    }
    for (var t = 0; t < _tracks.length; t++) {
      if (!usedT.contains(t)) _tracks[t].missed++;
    }
    for (var d = 0; d < dets.length; d++) {
      if (usedD.contains(d)) continue;
      final tr = _Track(_nextId++, dets[d].cx, dets[d].cy,
          math.max(dets[d].w, dets[d].h));
      _tracks.add(tr);
      out[tr.id] = (dets[d].cx, dets[d].cy);
    }
    _tracks.removeWhere((t) => t.missed > maxMissed);
    return out;
  }
}
