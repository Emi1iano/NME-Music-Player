import 'package:flutter/material.dart';
import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;
  final Color coverStart;
  final Color coverEnd;

  const Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    required this.coverStart,
    required this.coverEnd,
  });

  int get trackCount => tracks.length;
}
