class Song {
  final String path, title; // path is relative to the music folder
  const Song(this.path, this.title);
}

// Demo library. Replace with a scan of your music folder.
const library = [
  Song('ambient/dawn.mp3', 'Dawn Over the Valley'),
  Song('ambient/balloons.mp3', 'Slow Balloons'),
  Song('rock/highway.mp3', 'Highway Static'),
  Song('rock/ember.mp3', 'Ember Light'),
  Song('pop/golden.mp3', 'Golden Hour'),
  Song('pop/paper.mp3', 'Paper Skies'),
  Song('jazz/late.mp3', 'Late Train'),
  Song('jazz/blue.mp3', 'Blue Kettle'),
  Song('lofi/rain.mp3', 'Rain on Glass'),
  Song('lofi/tea.mp3', 'Tea at Four'),
  Song('folk/river.mp3', 'River Song'),
  Song('folk/oak.mp3', 'Old Oak'),
];
