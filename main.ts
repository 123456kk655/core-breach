// CORE BREACH — the entry's program.
//
// The game itself is a Rojo project in this directory: src/ holds every Luau script
// and `rojo build default.project.json --output game.rbxl` compiles it into the place
// file. This program does the hand-in: it stages the place, the sources, the
// screenshots and the play link into the output directory, then writes dossier.json
// with the vendored make.fun library, which is the text the judge reads.
//
// It runs on Node 22+ with the standard library only, writes the same bytes on every
// run, and touches no network. Outside the grader, MAKEFUN_OUTPUT_DIR stands in for
// /output:  node main.ts

import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildDossier } from './vendor/makefun-roblox.ts';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = process.env.MAKEFUN_OUTPUT_DIR ?? '/output';

/** The scorer's own caps: the dossier's text limit and the screenshot limits. */
const LIMITS = {
  text_max_bytes: 65536,
  screenshots: { max: 4, max_bytes: 262144 },
  max_instances: 500000,
  scripts_max_source_bytes: 8388608,
  scripts_max_path_chars: 1048576,
};

interface PlayLink {
  url: string;
  place_id: number;
  universe_id: number;
}

/** The published experience this entry hands in. Read and checked, never guessed. */
function readPlayLink(): PlayLink {
  const raw = JSON.parse(readFileSync(join(here, 'PLAY.json'), 'utf8')) as PlayLink;
  const numbers = Number.isInteger(raw.place_id) && raw.place_id > 0 && Number.isInteger(raw.universe_id) && raw.universe_id > 0;
  if (!numbers) {
    // Before the experience is published the ids are still 0, and the gate refuses the
    // entry on them. Say so loudly instead of writing a play link that cannot pass.
    console.warn('PLAY.json names no published place yet: place_id and universe_id must be positive integers');
  }
  return raw;
}

function stage(): PlayLink {
  const place = join(here, 'game.rbxl');
  if (!existsSync(place)) {
    throw new Error('game.rbxl is missing: run `rojo build default.project.json --output game.rbxl` first');
  }
  if (statSync(place).size > 32 * 1024 * 1024) {
    throw new Error('game.rbxl is over the 32 MiB cap');
  }

  mkdirSync(out, { recursive: true });
  copyFileSync(place, join(out, 'game.rbxl'));

  const play = readPlayLink();
  copyFileSync(join(here, 'PLAY.json'), join(out, 'PLAY.json'));

  cpSync(join(here, 'src'), join(out, 'src'), { recursive: true });
  mkdirSync(join(out, 'screenshots'), { recursive: true });
  if (existsSync(join(here, 'screenshots'))) {
    cpSync(join(here, 'screenshots'), join(out, 'screenshots'), { recursive: true });
  }
  return play;
}

const play = stage();
writeFileSync(join(out, 'dossier.json'), buildDossier(out, LIMITS));

console.log(`CORE BREACH staged in ${out}`);
console.log(`  play link: ${play.url}`);
console.log(`  dossier:   ${statSync(join(out, 'dossier.json')).size} bytes`);
