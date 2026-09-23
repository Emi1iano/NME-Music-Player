import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Hard-coded data so the UI can be built and demoed before the Zig
/// server + sync protocol are ready. Swap this out for real API calls
/// (see NmeApiClient, once you write it) without touching the widgets.
final List<Track> sampleTracks = [
  Track(
    id: 't1',
    title: 'Coastline Static',
    artist: 'Marrow',
    album: 'Low Tide EP',
    duration: const Duration(minutes: 3, seconds: 12),
    downloadedOffline: true,
  ),
  Track(
    id: 't2',
    title: 'Weekday Ghosts',
    artist: 'Palm Season',
    album: 'Weekday Ghosts',
    duration: const Duration(minutes: 4, seconds: 5),
    downloadedOffline: true,
  ),
  Track(
    id: 't3',
    title: 'Halide',
    artist: 'Marrow',
    album: 'Low Tide EP',
    duration: const Duration(minutes: 2, seconds: 48),
    downloadedOffline: false,
  ),
  Track(
    id: 't4',
    title: 'Amber Room',
    artist: 'Cassia Wren',
    album: 'Amber Room',
    duration: const Duration(minutes: 3, seconds: 37),
    downloadedOffline: true,
  ),
  Track(
    id: 't5',
    title: 'No Signal, No Static',
    artist: 'Palm Season',
    album: 'Weekday Ghosts',
    duration: const Duration(minutes: 5, seconds: 2),
    downloadedOffline: false,
  ),
  Track(
    id: 't6',
    title: 'Copper Line',
    artist: 'Deven Oaks',
    album: 'Copper Line',
    duration: const Duration(minutes: 3, seconds: 59),
    downloadedOffline: true,
  ),
];

final List<Playlist> samplePlaylists = [
  Playlist(
    id: 'p1',
    name: 'Late Shift',
    tracks: sampleTracks.sublist(0, 4),
    coverStart: const Color(0xFF4A4436),
    coverEnd: const Color(0xFF221F19),
  ),
  Playlist(
    id: 'p2',
    name: 'Offline for the drive',
    tracks: sampleTracks,
    coverStart: const Color(0xFF3D4A44),
    coverEnd: const Color(0xFF1A2320),
  ),
  Playlist(
    id: 'p3',
    name: 'Server room focus',
    tracks: sampleTracks.sublist(2, 6),
    coverStart: const Color(0xFF4A3D3D),
    coverEnd: const Color(0xFF231A1A),
  ),
];
