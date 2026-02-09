export function normalizeTheme(theme) {
  return theme === 'original' ? 'original' : 'shenzhen';
}

export function waveformFontFamily(theme) {
  return normalizeTheme(theme) === 'shenzhen' ? 'Share Tech Mono' : 'IBM Plex Mono';
}

export function waveformPalette(theme) {
  if (normalizeTheme(theme) === 'shenzhen') {
    return {
      bg: [8, 20, 18],
      axis: [66, 102, 85],
      grid: [46, 76, 62],
      label: [166, 198, 182],
      trace: [96, 234, 164],
      value: [244, 191, 102],
      time: [140, 164, 151],
      hint: [166, 198, 182]
    };
  }
  return {
    bg: [10, 21, 34],
    axis: [38, 74, 108],
    grid: [26, 56, 86],
    label: [152, 183, 217],
    trace: [61, 215, 194],
    value: [255, 188, 90],
    time: [153, 174, 200],
    hint: [170, 189, 212]
  };
}
