// Installs Terminal.app's mise-me profile and makes it the default. Run with:
//   osascript -l JavaScript terminal-app.js status DOMAIN FONT
//       prints: DEFAULT PROFILE <tab> STATE, where STATE says whether the
//       mise-me profile is current, outdated (differs from this file) or missing
//   osascript -l JavaScript terminal-app.js apply DOMAIN FONT
//       writes the mise-me profile into DOMAIN and makes it the default for
//       new windows and at startup. Settings it does not manage are kept.
//   osascript -l JavaScript terminal-app.js export FILE FONT
//       writes the profile to a .terminal file, which a running Terminal.app
//       imports with `open FILE`.
// DOMAIN is com.apple.Terminal (tests use a throwaway one). Only run `apply`
// while Terminal.app is closed: a running Terminal.app keeps its profiles in
// memory and writes them back over any change made here.
ObjC.import('Foundation');
ObjC.import('AppKit');

const NAME = 'mise-me';
const FONT_SIZE = 18;
// Gruvbox Material (github.com/sainnhe/gruvbox-material): dark, "medium"
// background, for the six ANSI colours that ls, git, syntax highlighting and
// friends use (black = bg5, bright colours = the normal ones). Plain text is
// not Gruvbox's tan (hard to read): it is near-white on a translucent dark
// navy, with a bluish selection, as in Terminal.app's "clear dark" style.
const COLOURS = {
  BackgroundColor: ['212734', 0.95],
  TextColor: ['e6e6e6', 1],
  TextBoldColor: ['f0f0f0', 1],
  CursorColor: ['e6e6e6', 1],
  SelectionColor: ['334e5e', 1],
};
const ANSI = {
  Black: '5a524c', Red: 'ea6962', Green: 'a9b665', Yellow: 'd8a657',
  Blue: '7daea3', Magenta: 'd3869b', Cyan: '89b482', White: 'dee5eb',
};
for (const [n, hex] of Object.entries(ANSI)) {
  COLOURS['ANSI' + n + 'Color'] = [hex, 1];
  COLOURS['ANSIBright' + n + 'Color'] = [hex, 1];
}
COLOURS.ANSIBrightWhiteColor = ['e5eff5', 1];
const NUMBERS = {
  BackgroundBlur: 0.5,
  BackgroundBlurInactive: 0,
  FontWidthSpacing: 1,
  FontHeightSpacing: 1,
  columnCount: 135,
  rowCount: 29,
};
const BOOLS = {
  BackgroundSettingsForInactiveWindows: true,
  DynamicANSIForegroundColors: false,
  FontAntialias: true,
  useOptionAsMetaKey: true,   // Option+Backspace etc. work on words
};

const rgb = hex => [0, 2, 4].map(i => parseInt(hex.slice(i, i + 2), 16) / 255);
const archive = o => $.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(o, false, null);
const unarchive = d => (d.isNil() || !d.isKindOfClass($.NSData)) ? $() : $.NSKeyedUnarchiver.unarchiveObjectWithData(d);

function colourMatches(data, [hex, alpha]) {
  const c = unarchive(data);
  if (c.isNil() || !c.isKindOfClass($.NSColor)) return false;
  const s = c.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
  if (s.isNil()) return false;
  const [r, g, b] = rgb(hex);
  const near = (x, y) => Math.abs(x - y) < 0.6 / 255;
  return near(s.redComponent, r) && near(s.greenComponent, g) && near(s.blueComponent, b) &&
    Math.abs(s.alphaComponent - alpha) < 0.005;
}

// state(profile, fontName): 'current' when every managed setting matches.
function state(profile, fontName) {
  if (profile.isNil()) return 'missing';
  for (const [k, v] of Object.entries(COLOURS)) {
    if (!colourMatches(profile.objectForKey(k), v)) return 'outdated';
  }
  for (const [k, v] of Object.entries(NUMBERS)) {
    const n = profile.objectForKey(k);
    if (n.isNil() || Math.abs(n.doubleValue - v) > 1e-6) return 'outdated';
  }
  for (const [k, v] of Object.entries(BOOLS)) {
    const n = profile.objectForKey(k);
    if (n.isNil() || n.boolValue !== v) return 'outdated';
  }
  const font = unarchive(profile.objectForKey('Font'));
  if (font.isNil() || !font.isKindOfClass($.NSFont) ||
    ObjC.unwrap(font.fontName) !== fontName || font.pointSize !== FONT_SIZE) return 'outdated';
  return 'current';
}

// build(base, fontName): the mise-me profile, on top of BASE (an existing
// mise-me profile, so settings changed by hand that are not managed here stay).
function build(base, fontName) {
  const font = $.NSFont.fontWithNameSize(fontName, FONT_SIZE);
  if (font.isNil()) throw new Error('font is not installed: ' + fontName);
  const p = base.isNil() ? $.NSMutableDictionary.dictionary : base.mutableCopy;
  const set = (k, v) => p.setObjectForKey(v, k);
  set('name', $(NAME));
  set('type', $('Window Settings'));
  set('ProfileCurrentVersion', $.NSNumber.numberWithDouble(2.09));
  for (const [k, [hex, alpha]] of Object.entries(COLOURS)) {
    const [r, g, b] = rgb(hex);
    set(k, archive($.NSColor.colorWithSRGBRedGreenBlueAlpha(r, g, b, alpha)));
  }
  for (const [k, v] of Object.entries(NUMBERS)) set(k, $.NSNumber.numberWithDouble(v));
  for (const [k, v] of Object.entries(BOOLS)) set(k, $.NSNumber.numberWithBool(v));
  set('Font', archive(font));
  return p;
}

function run(argv) {
  const [mode, target, fontName] = argv;
  if (!fontName || !['status', 'apply', 'export'].includes(mode)) {
    throw new Error('usage: status DOMAIN FONT | apply DOMAIN FONT | export FILE FONT');
  }
  if (mode === 'export') {
    if (!build($(), fontName).writeToFileAtomically(target, true)) throw new Error('could not write ' + target);
    return target;
  }

  const defaults = $.NSUserDefaults.alloc.initWithSuiteName(target);
  const current = ObjC.unwrap(defaults.stringForKey('Default Window Settings')) || 'Basic';
  const all = defaults.dictionaryForKey('Window Settings');
  const mine = all.isNil() ? all : all.objectForKey(NAME);
  if (mode === 'status') return [current, state(mine, fontName)].join('\t');

  const updatedAll = all.isNil() ? $.NSMutableDictionary.dictionary : all.mutableCopy;
  updatedAll.setObjectForKey(build(mine, fontName), NAME);
  defaults.setObjectForKey(updatedAll, 'Window Settings');
  defaults.setObjectForKey($(NAME), 'Default Window Settings');
  defaults.setObjectForKey($(NAME), 'Startup Window Settings');
  if (!defaults.synchronize) throw new Error('could not save Terminal.app settings');
  return [NAME, 'current'].join('\t');
}
