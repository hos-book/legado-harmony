// Original vector companions to the Dreamina-generated obsidian/champagne artwork.
import { writeFileSync } from 'node:fs';
const root = new URL('../entry/src/main/resources/base/media/', import.meta.url);
const svg = (w,h,body) => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${body}</svg>\n`;
const save = (name,w,h,body) => writeFileSync(new URL(name+'.svg',root),svg(w,h,body));
const star = (x,y,s,c) => `<path d="M${x} ${y-s}Q${x} ${y} ${x+s} ${y}Q${x} ${y} ${x} ${y+s}Q${x} ${y} ${x-s} ${y}Q${x} ${y} ${x} ${y-s}Z" fill="${c}"/>`;
for(const mode of ['light','dark']) {
  const gold = mode==='light'?'#A38A57':'#9E865B', ink=mode==='light'?'#C9C0AF':'#4B4840';
  const corner=`<g fill="none" stroke="${gold}" stroke-width="1.5" opacity="0.28"><path d="M16 180V16H180M25 148V25H148"/><path d="M38 97C72 53 121 37 180 50M38 114C80 65 130 51 210 64"/><circle cx="65" cy="65" r="27"/><path d="M30 145L48 128 64 134 88 102 115 116 140 92"/></g>${star(141,35,5,gold)}${star(37,171,3,gold)}`;
  const trailing=`<g fill="none" stroke="${gold}" stroke-width="1.5" opacity="0.26"><path d="M300 464H464V300M332 455H455V332"/><path d="M322 418C349 398 376 402 392 414C414 397 437 402 444 414L444 440C422 427 406 430 392 440C372 428 347 427 322 440Z"/><path d="M392 414V440M332 418C349 411 372 411 385 420M399 421C412 412 425 413 437 418"/><path d="M310 400Q367 360 442 380"/></g>${star(425,357,5,gold)}${star(307,432,3,ink)}`;
  save(`reader_decor_obsidian_archive_${mode}`,480,480,corner);
  save(`reader_decor_obsidian_archive_trailing_${mode}`,480,480,trailing);
  save(`reader_bg_obsidian_archive_${mode}`,1080,1920,`<rect width="1080" height="1920" fill="${mode==='light'?'#F8F3E9':'#191B1F'}"/>`);
  // Fine architecture and paper arcs live above the player controls; no heavy central motif.
  save(`tts_panel_obsidian_archive_${mode}`,720,520,
    `<g fill="none" stroke="${gold}" opacity="0.32" stroke-width="1.5"><path d="M40 280V130A96 96 0 0 1 232 130V250M50 276V132A86 86 0 0 1 222 132V246"/><path d="M414 246Q515 140 680 190M440 264Q535 183 700 220"/><path d="M80 278Q151 247 210 279L210 301Q147 272 80 301ZM210 279Q260 250 314 271V296Q258 277 210 301"/><path d="M85 320H650"/><circle cx="556" cy="96" r="31"/><circle cx="556" cy="96" r="42"/></g>${star(352,80,7,gold)}${star(633,145,5,gold)}${star(398,200,4,gold)}`);
}
save('theme_frame_obsidian_archive',450,660,
  '<g fill="none" stroke="#C5AA73"><rect x="6" y="6" width="438" height="648" rx="10" stroke-width="2" opacity="0.65"/><path d="M16 70V16H70M380 16H434V70M434 590V644H380M70 644H16V590" stroke-width="1" opacity="0.55"/></g>'+star(225,12,4,'#D6B878')+star(225,648,4,'#D6B878'));
save('theme_logo_obsidian_archive',64,64,
  '<rect x="3" y="3" width="58" height="58" rx="15" fill="#191B1F"/><g fill="none" stroke="#D6B878" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 40Q22 36 32 42Q42 36 52 40V48Q41 44 32 50Q23 44 12 48Z"/><path d="M32 42V50M32 26C19 10 8 23 17 31C24 38 37 17 45 19C58 22 46 44 32 26"/></g>');
save('regex_frame_gilded_orbit',96,48,'<rect x="2" y="3" width="92" height="42" rx="8" fill="none" stroke="#B59B68" stroke-width="1" opacity="0.55"/><path d="M9 11H19M77 37H87" stroke="#D6B878" fill="none"/>');
save('regex_cap_gilded_orbit',24,48,star(12,24,6,'#B59B68'));
const nav={
  bookshelf:'M3 4h4v16H3zM9 4h4v16H9zM15 5l4-1 4 15-4 1z',
  explore:'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm5 5-3 7-7 3 3-7 7-3Zm-5 4a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z',
  search:'M10 2a8 8 0 1 0 4.9 14.3l5.4 5.4 1.4-1.4-5.4-5.4A8 8 0 0 0 10 2Zm0 2a6 6 0 1 1 0 12 6 6 0 0 1 0-12Z',
  mine:'M12 2a5 5 0 1 0 0 10 5 5 0 0 0 0-10Zm0 12c-5 0-9 3-9 7v1h18v-1c0-4-4-7-9-7Z'
};
for(const [name,d] of Object.entries(nav)) save('ic_theme_obsidian_archive_'+name,24,24,`<path d="${d}" fill="#000000" fill-rule="evenodd"/>`);
console.log('Generated obsidian theme vector companions.');
