# Glass Bridge — Design Fundamentals

Research notes on the most popular Roblox glass bridge games (October 2026), boiled down to what
our game needs.

## 1. What's popular right now

| Game | Creator | Visits | Hook |
|---|---|---|---|
| The $1,000,000 Glass Bridge | Equity | ~112M | Big "prize" framing; classic random bridge |
| KPop Demon Hunters Glass Bridge | Apex Tech. | ~67–73M | Trending IP theme; "unlock helicopters" |
| The Glass Bridge | ItsZeddex | ~36M | Classic Squid Game bridge |
| Logo Glass Bridge | IV Developments | ~32–38M | **Quiz bridge**: pick the panel with the right logo |
| 67 Glass Bridge | Apex Tech. | ~13M | Meme theme |
| 100 Players Glass Bridge | Colorful Coconut | ~6M | Big lobbies, chaos |

Apex Tech. alone runs Math, Country, Logo, Memory and Color variants of the same bridge, so
**one bridge engine with swappable themes** is the business model.

Visit numbers come from third-party trackers (Rotrends, Bloxodes, RoWatcher), so treat them as
approximate.

## 2. The core loop (every game has this)

1. Spawn on a **start platform**.
2. In front of you is a bridge of **rows**. Each row has **2 panels** (left/right) and some
   variants have 3–4 at harder stages.
3. Exactly **one panel per row is safe**. The other one **shatters** when you step on it.
4. You fall into the void, respawn at the start (or last checkpoint), and try again.
5. Reach the **end platform**, get rewards, then either loop back to the start or go on to a harder bridge.

The whole game is that tension: *which panel?* It's short, easy to understand in 2 seconds, and
very clippable. Keep it that way.

## 3. Bridge variants (the "theme" layer)

- **Classic / random**: pure luck. Safe side randomised per row. The only skill is watching
  other players and **remembering** which panels have already broken or been stepped on safely.
- **Quiz bridge** (Math, Logo, Country, Flag): each row shows a question, and each panel shows an
  answer. The correct answer is the safe panel. Of these the variant with the best current
  numbers is Logo, peaking around 3K concurrent players in Oct 2026.
- **Memory bridge**: the safe path flashes briefly at the start, then you cross from memory.
- **Colour bridge**: the safe colour is called out per row.
- **Themed skins** (KPop, 67, memes): same bridge with trending IP or meme visuals. Cheap to make and
  good for search traffic.

## 4. Fundamental rules to get right

**Safe-path generation (server only)**
- The server picks the safe panel for each row. The client must never receive this until the
  panel is stepped on, or exploiters will just read it.
- Re-roll the path every round, or on a timer like "randomized glass each time".
- Decide whether the path is **shared** (everyone sees the same bridge, which makes it social because
  people learn from each other's deaths) or **per-player**. Popular games share it.

**Breaking**
- Detect the step on the server with `Touched`/region check plus a character check. The client can do
  instant visual feedback but the server owns the result.
- Wrong panel: shatter effect (glass sound, fragments) and the panel goes non-collide. Players fall.
- Correct panel: optionally tint green or leave it. Many games leave breadcrumbs, because broken
  panels reveal the path to everyone who's watching.
- Reset panels when the round restarts, or after N seconds.

**Falling**
- The baseplate area around the bridge is the void. Roblox kills at `FallenPartsDestroyHeight`
  (-500). For faster respawns, add a kill zone ~30 studs below the bridge.
- Respawn fast (1–2 s). Slow respawn kills retention in this genre.

**Checkpoints / progression**
- Long bridges get **checkpoints** every ~10 rows.
- After finishing, offer a harder bridge with more rows, more panels per row, smaller panels or moving panels.

**Social / multiplayer**
- "Play with your friends" is in nearly every description. Other players dying ahead of you is the
  main source of information *and* the main source of fun.
- Optional **trolling**: some games sell or award **Push** (shove a player off), walls and decoy
  tricks. It's great for clips but frustrating, so make it opt-in or limited-use.

## 5. Rewards & monetization patterns seen

- **Wins / coins** for finishing, shown on a leaderboard (leaderstats). This drives replay.
- Points for being **first to find a safe tile** (one game gives 10 per tile and 1000 per finish).
- Spendable on **abilities**: Push, "Glass Checker" (reveals one panel), shields, speed.
- **Skip / helicopter** products that fly you over the bridge (Apex Tech. games advertise this).
- Gamepasses: 2× wins, VIP, trails/cosmetics, extra lives.
- **Don't** promise real Robux prizes. "$1,000,000" titles are framing only. Promising
  Robux payouts breaks Roblox rules and many clones add disclaimers.

## 6. Build plan for this project (minimum viable game)

Map to our Rojo layout:

| Piece | Where | What it does |
|---|---|---|
| `BridgeConfig` | `src/shared` (ReplicatedStorage.Shared) | Rows, panel size, gap, panels per row, theme |
| `BridgeService` | `src/server` | Builds the bridge, picks the safe path, handles touches and breaking, round resets |
| `CheckpointService` | `src/server` | Saves the furthest checkpoint per player and respawns them there |
| `RewardService` | `src/server` | leaderstats Wins/Coins, then DataStore persistence later |
| `BridgeEffects` | `src/client` | Shatter particles and sound, camera shake, UI for quiz questions |

Milestones:
1. **MVP**: start and end platforms, 15 rows × 2 panels, random safe side, wrong panel breaks,
   void kills, finishing gives +1 Win.
2. **Feel**: shatter effects, sounds, fast respawn, round reset timer.
3. **Retention**: checkpoints, harder bridge 2, leaderboard, saved data.
4. **Variant**: quiz mode (Math is easiest to generate procedurally).
5. **Monetization**: skip product, 2× wins pass, cosmetics, limited Push.

## Sources

- [The $1,000,000 Glass Bridge stats (Bloxodes)](https://bloxodes.com/stats/games/the-1-000-000-glass-bridge-6821120514)
- [KPop Demon Hunters Glass Bridge (RoWatcher)](https://rowatcher.com/games/8349306677/kpop-demon-hunters-glass-bridge)
- [Logo Glass Bridge (RoWatcher)](https://rowatcher.com/games/9572842965/logo-glass-bridge)
- [The Glass Bridge stats (Bloxodes)](https://bloxodes.com/stats/games/the-glass-bridge-3097398008)
- [67 Glass Bridge stats (Bloxodes)](https://bloxodes.com/stats/games/67-glass-bridge-8682706929)
- [100 Players Glass Bridge (RoWatcher)](https://rowatcher.com/games/10345973434/100-players-glass-bridge)
- [How to play Impossible Squid Game Glass Bridge 2 (Sportskeeda)](https://www.sportskeeda.com/roblox-news/how-play-impossible-squid-game-glass-bridge-2)
- [How to push players in Shrimp Game (Sportskeeda)](https://www.sportskeeda.com/roblox-news/how-push-players-shrimp-game)
