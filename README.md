# CarrotSwap

A World of Warcraft: **Forever** addon that equips **Carrot on a Stick** whenever you mount, and puts your normal trinket back when you dismount.

## Install

1. Download **CarrotSwap.zip** from the [Releases](../../releases) page (not the green "Code" button).
2. Unzip it into your Forever `Interface\AddOns` folder, so you end up with `Interface\AddOns\CarrotSwap\CarrotSwap.toc`.
3. Fully restart the game.

## How it works

- **Mount up** → Carrot on a Stick goes into your bottom trinket slot, and CarrotSwap remembers the trinket it replaced.
- **Dismount** → that trinket goes back on.
- **Combat** → WoW doesn't allow trinket swaps in combat. If you get dazed off your mount mid-fight, the swap happens the moment combat ends.
- **Reloads and logouts** → it remembers the swapped-out trinket per character, so it still puts it back after a `/reload` or relog.
- **Leaves your choices alone** → if you put the carrot on yourself, it won't take it off. Flight paths don't count as mounting.
- Keep the carrot in your bags. If it's missing, you get one warning and nothing is swapped.

## Self-check

Every couple of seconds (out of combat) CarrotSwap checks that you're wearing the carrot while mounted and your normal trinket on foot, and fixes it if a swap didn't take. It remembers your normal trinkets while you're on foot, so it can still put the right one back if a swap got lost. Use `/carrot off` if you ever want to wear the carrot on foot.

## Commands

| Command | What it does |
|---|---|
| `/carrot` | Show status (on/off, which slot, what it's holding) |
| `/carrot on` / `/carrot off` | Turn swapping on or off |
| `/carrot slot 1` / `/carrot slot 2` | Use the top or bottom trinket slot (default: bottom) |
| `/carrot item <shift-click a trinket>` | Swap in a different mount trinket |
| `/carrot item reset` | Back to Carrot on a Stick |
| `/carrot back` | Put your saved trinket back right now instead of waiting for the next check |
| `/carrot quiet` | Turn the swap messages in chat on or off |
| `/carrot debug` | Explain each swap step in chat, for troubleshooting |
