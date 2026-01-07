class AnalysisResult {
  final String? prediction;
  final double? confidence;
  final Map<String, dynamic>? probabilities;
  final List<FramePrediction>? framePredictions;
  final VideoMetadata? videoMetadata;

  AnalysisResult({
    this.prediction,
    this.confidence,
    this.probabilities,
    this.framePredictions,
    this.videoMetadata,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      prediction: json['prediction'],
      confidence: json['confidence'] != null ? (json['confidence'] as num).toDouble() : null,
      probabilities: json['probabilities'],
      framePredictions: json['frame_predictions'] != null
          ? (json['frame_predictions'] as List)
              .map((e) => FramePrediction.fromJson(e))
              .toList()
          : null,
      videoMetadata: json['video_metadata'] != null
          ? VideoMetadata.fromJson(json['video_metadata'])
          : null,
    );
  }
}

class FramePrediction {
  final int frameNumber;
  final String prediction;
  final double confidence;
  final double timestamp;
  final String timestampFormatted;

  FramePrediction({
    required this.frameNumber,
    required this.prediction,
    required this.confidence,
    required this.timestamp,
    required this.timestampFormatted,
  });

  factory FramePrediction.fromJson(Map<String, dynamic> json) {
    return FramePrediction(
      frameNumber: json['frame_number'] ?? 0,
      prediction: json['prediction'] ?? 'Unknown',
      confidence: json['confidence'] != null ? (json['confidence'] as num).toDouble() : 0.0,
      timestamp: json['timestamp'] != null ? (json['timestamp'] as num).toDouble() : 0.0,
      timestampFormatted: json['timestamp_formatted'] ?? '',
    );
  }
}

class VideoMetadata {
  final double duration;
  final int totalFrames;
  final double fps;

  VideoMetadata({
    required this.duration,
    required this.totalFrames,
    required this.fps,
  });

  factory VideoMetadata.fromJson(Map<String, dynamic> json) {
    return VideoMetadata(
      duration: json['duration'] != null ? (json['duration'] as num).toDouble() : 0.0,
      totalFrames: json['total_frames'] ?? 0,
      fps: json['fps'] != null ? (json['fps'] as num).toDouble() : 0.0,
    );
  }
}
