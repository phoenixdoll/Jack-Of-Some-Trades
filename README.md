# Jack of Some Trades

Ties trade and crafting skills to the traits and profession picked at character creation, so a character's skill ceiling (and starting level) reflects their actual backstory instead of every survivor eventually maxing every skill regardless of what they picked.

## Skill Caps
The number of pips you pick in a skill at character creation determines the maximum level you can ever achieve in the skill. All combat skills, passive skills, agility skills are exempt from skill caps. The exception is Maintenance which is capped per the below.
```
       chosen  |
         pips  | cap
            0  |  3
            1  |  5
            2  |  7
            3  |  9
            4+ |  10
```

**Skill pairs:** If you take even one point in the skill it raises the other's cap/ceiling by 1.

```
Animal Care ↔ Pottery
Animal Care ↔ First Aid
Agriculture ↔ Glassmaking
Agriculture ↔ Animal Care
Agriculture ↔ Foraging
Butchering ↔ Animal Care
Butchering ↔ Cooking
Butchering ↔ Fishing
Blacksmithing ↔ Welding
Blacksmithing ↔ Glassmaking
Blacksmithing ↔ Tailoring
Carpentry ↔ Carving
Carpentry ↔ Masonry
Carving ↔ Tailoring
Cooking ↔ First Aid
Cooking ↔ Fishing
Electrical ↔ Mechanics
Electrical ↔ Carpentry
Electrical ↔ Welding
First Aid ↔ Tailoring
Fishing ↔ Tracking
Foraging ↔ Tracking
Knapping ↔ Carving
Knapping ↔ Trapping
Knapping ↔ Masonry
Glassmaking ↔ Pottery
Masonry ↔ Pottery
Mechanics ↔ Welding
Mechanics ↔ Agriculture
Trapping ↔ Foraging
Trapping ↔ Tracking
Maintenance ↔ Carpentry
Maintenance ↔ Welding
Maintenance ↔ Blacksmithing
Maintenance ↔ Tailoring
Maintenance ↔ Carving
```

## Skill boosts:
Your starting skill level is set once you exit character creation, based on your chosen pips in that skill. This never affects the cap above -- caps are always pip-based regardless of which (if any) training trait you pick.

By default (no training trait picked):
```
     chosen    |
      pips     | starting skill
            0  |  0
            1  |  2
            2  |  4
            3  |  6
            4+ |  7
```

Four optional, mutually-exclusive traits change which table applies. Unlike the default table above, these do more than just skip a bonus -- picking one of them can pull your starting level *below* whatever vanilla itself would have already granted from your profession/trait pips, since the whole point is to start with less than your background alone would imply.

**Experienced** (costs 2 points) -- the strongest table:
```
     chosen    |
      pips     | starting skill
            0  |  0
            1  |  3
            2  |  5
            3  |  7
            4+ |  9
```

**Self Taught** (grants 2 points) -- vanilla behavior: no bonus at all, starting skill equals your pips exactly. If you prefer the vanilla grind, pick this for some free trait points.
```
     chosen    |
      pips     | starting skill
            0  |  0
            1  |  1
            2  |  2
            3  |  3
            4+ |  the value of the pip
```

**Unfinished Education** (grants 4 points) -- half of Self Taught's level, rounded down.
```
     chosen    |
      pips     | starting skill
            0  |  0
            1  |  0
            2  |  1
            3  |  1
            4+ |  half the value, rounded down
```

**Blank Slate** (grants 6 points) -- always start every trade skill at 0, no matter your pips. Your cap is still set by your pips as normal, and you still get any XP-rate bonuses from them -- you just have to earn every level yourself.
```
     chosen    |
      pips     | starting skill
            0  |  0
            1  |  0
            2  |  0
            3  |  0
            4+ |  0
```