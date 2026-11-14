"""Writes Super Auction House's recipe list (RecipeData.lua) from WoW Forever's own client tables.

Reads SkillLineAbility, SpellReagents, SpellEffect, SpellName and TradeSkillCategory for a build from wago.tools
(product wowf) and applies the live hotfixes wago has recorded for the recipe tables. A recipe is listed when it's in
one of a profession's own categories (so Season of Discovery recipes, which the client files under a category of their
own, and uncategorized rows such as profession ranks are left out), has a name and takes materials.

Usage: python -I tools/recipe_data.py [--build 1.60.1.70938] [--cache DIR]
"""
import argparse
import collections
import csv
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
OUT = PROJECT / 'HastesSuperTweaks' / 'Modules' / 'SuperAuctionHouse' / 'RecipeData.lua'
AGENT = {'User-Agent': 'Mozilla/5.0 (recipe_data.py)'}

# Professions whose recipes are listed, by skill line, in the order the list shows them.
PROFESSIONS = [
    (171, 'Alchemy'), (164, 'Blacksmithing'), (185, 'Cooking'), (333, 'Enchanting'), (202, 'Engineering'),
    (129, 'First Aid'), (165, 'Leatherworking'), (186, 'Mining'), (197, 'Tailoring'),
]
CREATE_ITEM, ENCHANT_ITEM = 24, 53
TABLES = ['SkillLineAbility', 'SpellReagents', 'SpellEffect', 'SpellName', 'TradeSkillCategory', 'Item']
HOTFIX_TABLES = ['SpellReagents', 'SkillLineAbility', 'TradeSkillCategory']


def fetch(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=120) as r:
                return r.read().decode('utf-8')
        except OSError:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def latest_build():
    builds = json.loads(fetch('https://wago.tools/api/builds'))
    return builds['wowf'][0]['version']


def table(cache, build, name):
    path = cache / f'{name}-{build}.csv'
    if not path.exists():
        path.write_text(fetch(f'https://wago.tools/db2/{name}/csv?build={build}'), encoding='utf-8')
    with path.open(encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def hotfixes(cache, build, name):
    """The hotfix records wago has for a table at this build: {record_id: row as a list, or None when deleted}."""
    path = cache / f'hotfix-{name}-{build}.json'
    if not path.exists():
        rows, page = [], 1
        number = build.rsplit('.', 1)[1]
        while True:
            query = urllib.parse.urlencode({'search': f'{number} {name.lower()}', 'page': page})
            text = fetch('https://wago.tools/hotfixes?' + query)
            props = json.loads(html.unescape(re.search(r'data-page="([^"]+)"', text).group(1)))['props']
            found = props['hotfixes']
            rows += [r for r in found['data'] if r['table_name'] == name and str(r['build']) == number]
            if page >= found['last_page']:
                break
            page += 1
            time.sleep(0.3)
        path.write_text(json.dumps(rows), encoding='utf-8')
    rows = json.loads(path.read_text(encoding='utf-8'))
    latest = {}
    for r in sorted(rows, key=lambda r: (r['push_id'], r['id'])):
        if r['status'] == 1 and r['data'] is not None:
            latest[r['record_id']] = r['data']
        elif r['status'] == 2:
            latest[r['record_id']] = None
    return latest


def flatten(value):
    out = []
    for v in value:
        if isinstance(v, list):
            out += flatten(v)
        else:
            out.append(v)
    return out


def apply_hotfixes(rows, fixes):
    """Rows by ID with the hotfixes on them. A fixed row's values are in the CSV's column order."""
    by_id = {r['ID']: r for r in rows}
    if not rows:
        return by_id
    columns = list(rows[0].keys())
    for record, data in fixes.items():
        key = str(record)
        if data is None:
            by_id.pop(key, None)
            continue
        values = flatten(data)
        if len(values) != len(columns):
            sys.exit(f'Hotfix for record {record} has {len(values)} values, the table {len(columns)}')
        fixed = {c: str(v) for c, v in zip(columns, values)}
        # wago records some hotfixes from other locales' clients, so a row's text stays the English the CSV has.
        old = by_id.get(key)
        if old:
            for c in columns:
                if c.endswith('_lang'):
                    fixed[c] = old[c]
        elif any(ord(ch) > 127 for c in columns if c.endswith('_lang') for ch in fixed[c]):
            sys.exit(f'Hotfix for record {record} adds a row whose text isn\'t English: {fixed}')
        by_id[key] = fixed
    return by_id


def lua_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', help='a wowf build such as 1.60.1.70938 (default: the newest)')
    parser.add_argument('--cache', default=str(PROJECT / '.cache' / 'recipe_data'))
    args = parser.parse_args()
    build = args.build or latest_build()
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    data = {name: table(cache, build, name) for name in TABLES}
    fixes = {name: hotfixes(cache, build, name) for name in HOTFIX_TABLES}

    abilities = apply_hotfixes(data['SkillLineAbility'], fixes['SkillLineAbility'])
    reagents = {r['SpellID']: r for r in apply_hotfixes(data['SpellReagents'], fixes['SpellReagents']).values()}
    categories = apply_hotfixes(data['TradeSkillCategory'], fixes['TradeSkillCategory'])
    names = {r['ID']: r['Name_lang'] for r in data['SpellName']}
    items = {r['ID'] for r in data['Item']}
    effects = collections.defaultdict(list)
    for r in data['SpellEffect']:
        if r['DifficultyID'] == '0':
            effects[r['SpellID']].append(r)

    wanted = {str(skill) for skill, _ in PROFESSIONS}
    by_category = collections.defaultdict(dict)
    skipped = collections.Counter()
    for a in abilities.values():
        if a['SkillLine'] not in wanted:
            continue
        spell = a['Spell']
        category = categories.get(a['TradeSkillCategoryID'])
        # A profession's own categories sit under its top category; Season of Discovery's has none above it.
        if not category or category['ParentTradeSkillCategoryID'] == '0':
            skipped['no category of the profession'] += 1
            continue
        if not names.get(spell):
            skipped['no name'] += 1
            continue
        row = reagents.get(spell)
        mats = []
        if row:
            for i in range(8):
                item, count = row[f'Reagent_{i}'], int(row[f'ReagentCount_{i}'])
                if item != '0' and count > 0:
                    mats.append((int(item), count))
        if not mats:
            skipped['no materials'] += 1
            continue
        missing = [m for m, _ in mats if str(m) not in items]
        if missing:
            skipped['a material the client lacks'] += 1
            continue
        made, count = 0, 0
        for e in sorted(effects[spell], key=lambda e: int(e['EffectIndex'])):
            if int(e['Effect']) == CREATE_ITEM and e['EffectItemType'] != '0':
                made, count = int(e['EffectItemType']), max(1, round(float(e['EffectBasePointsF'])))
                break
        kind = 'item' if made else 'enchant' if any(int(e['Effect']) == ENCHANT_ITEM for e in effects[spell]) \
            else 'other'
        skipped['listed: ' + kind] += 1
        skill = int(a['TrivialSkillLineRankLow'])
        by_category[category['ID']][int(spell)] = (skill, made, count, mats)

    lines = [
        '-- Every WoW Forever recipe that takes materials, by profession and category: what it makes and what it takes.',
        f'-- Generated by tools/recipe_data.py from the game\'s client tables, build {build}, with its hotfixes. Run the',
        '-- script again after a patch instead of editing this file.',
        '-- A category\'s recipes: "spellID:skill:itemID:count:material*n,material*n;..." with itemID 0 for one that',
        '-- makes no item (an enchantment). The skill is where the recipe turns yellow.',
        '-- SPDX-License-Identifier: MPL-2.0',
        'local ADDON, ns = ...',
        'ns.SuperAuctionHouse.RecipeData = {',
        f'    build = "{build}",',
    ]
    total = 0
    for skill, profession in PROFESSIONS:
        cats = [c for c in categories.values() if c['ID'] in by_category
                and any(a['SkillLine'] == str(skill) and a['TradeSkillCategoryID'] == c['ID']
                        for a in abilities.values())]
        cats.sort(key=lambda c: (int(c['OrderIndex']), c['Name_lang']))
        lines.append(f'    {{ {skill}, {lua_string(profession)},')
        for c in cats:
            recipes = by_category[c['ID']]
            parts = []
            for spell, (rank, made, count, mats) in sorted(recipes.items(), key=lambda kv: (kv[1][0], names[str(kv[0])])):
                parts.append(f'{spell}:{rank}:{made}:{count}:' + ','.join(f'{m}*{n}' for m, n in mats))
            total += len(parts)
            lines.append(f'        {{ {c["ID"]}, {lua_string(c["Name_lang"])}, "' + ';'.join(parts) + '" },')
        lines.append('    },')
    lines.append('}')
    OUT.write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print(f'Wrote {total} recipes from build {build} to {OUT.relative_to(PROJECT)}')
    for reason, n in sorted(skipped.items()):
        print(f'  {reason}: {n}')


if __name__ == '__main__':
    main()
