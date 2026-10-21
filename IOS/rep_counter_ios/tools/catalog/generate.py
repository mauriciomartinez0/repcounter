"""Builds the catalog additions from the curated list.

Outputs:
  - rep_counter_api/db/migrations/003_dataset_exercises.sql
  - rep_counter_api/db/migrations/004_weight_stack.sql
  - rep_counter_ios/Sources/RepCounter/Resources/Catalog/catalog.json (seed)
  - rep_counter_ios/Sources/RepCounter/Resources/ExerciseImages/<id>.jpg
  - rep_counter_ios/Sources/RepCounter/Resources/ExercisePhotos/<id>-0.jpg, -1.jpg
    (free-exercise-db photos, start and end position, when there is a match)
  - rep_counter_ios/Sources/RepCounter/Resources/ExerciseAnimations/<id>.gif
    (dataset animation, only for exercises without photos)

Usage: python3 generate.py <exercises-dataset clone> [photo cache dir]
"""

import json
import re
import shutil
import urllib.request
from pathlib import Path

from PIL import Image

from curated import EXISTING, NEW, SELECTOR_MACHINES, STACK_NOTE, STACK_PROFILE
from photos import PHOTOS

HERE = Path(__file__).parent
# Clone of https://github.com/hasaneyldrm/exercises-dataset (pass its path).
import sys
DATASET = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "exercises-dataset"
ROOT = Path("/home/mauro/Documents/projects/aunnotienenombre")
API = ROOT / "rep_counter_api"
IOS = ROOT / "IOS" / "rep_counter_ios" / "Sources" / "RepCounter" / "Resources"

NOTES = {
    "bar": "Sobre la barra, en el centro.",
    "dumbbell": "En el mango de la mancuerna.",
    "machine": "En el brazo de la máquina, cerca del agarre.",
    "cable": "En el agarre de la polea.",
    "wrist": "En el antebrazo, cerca de la muñeca.",
    "waist": "En la cintura o en una mochila pegada a la espalda.",
}

dataset = {e["id"]: e for e in json.load(open(DATASET / "data" / "exercises.json"))}


def default_placement(equipment):
    return {"barbell": "equipment", "machine": "equipment", "dumbbell": "arm",
            "cable": "arm", "bodyweight": "body"}[equipment]


def note(our_id, equipment, placement):
    if placement == "arm":
        return NOTES["wrist"]
    if placement == "body":
        return NOTES["waist"]
    if our_id.startswith("smith-") or equipment == "barbell":
        return NOTES["bar"]
    return NOTES[{"machine": "machine", "dumbbell": "dumbbell", "cable": "cable"}.get(equipment, "waist")]


def steps(dataset_id):
    raw = dataset[dataset_id]["instruction_steps"]["es"]
    return [s.strip() for s in raw if s.strip()]


def sql(text):
    return "'" + text.replace("'", "''") + "'"


# --- Parse the current catalog from migration 002 ---------------------------

seed_sql = (API / "db/migrations/002_seed_exercises.sql").read_text()
row = re.compile(
    r"\('([a-z0-9-]+)', '((?:[^']|'')*)', '(\w+)', '(\w+)', '(\w+)', '((?:[^']|'')*)', (\d+), (\d+)\)")
current = []
for m in row.finditer(seed_sql):
    current.append(dict(id=m[1], name=m[2].replace("''", "'"), muscleGroup=m[3], equipment=m[4],
                        placement=m[5], placementNote=m[6].replace("''", "'"),
                        firmwareProfile=int(m[7]), tutorialSeconds=int(m[8])))
assert len(current) == 32, len(current)
assert {e["id"] for e in current} == set(EXISTING), "EXISTING out of sync with 002"

# Steps that 002 already wrote (bench press and push-up).
step_rows = re.findall(r"\('([a-z0-9-]+)', (\d+), '((?:[^']|'')*)'\)", seed_sql)
current_steps = {}
for ex_id, pos, body in step_rows:
    current_steps.setdefault(ex_id, []).append(body.replace("''", "'"))

# --- Validate the new list ------------------------------------------------------

ids = [e["id"] for e in current]
names = [e["name"] for e in current]
new_rows = []
for ds_id, our_id, name, group, equipment, placement in NEW:
    assert ds_id in dataset, ds_id
    assert re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", our_id), our_id
    assert group in {"chest", "back", "legs", "shoulders", "arms", "core"}, our_id
    assert equipment in {"barbell", "dumbbell", "machine", "bodyweight", "cable"}, our_id
    placement = placement or default_placement(equipment)
    ids.append(our_id)
    names.append(name)
    new_rows.append(dict(
        id=our_id, name=name, muscleGroup=group, equipment=equipment, placement=placement,
        placementNote=note(our_id, equipment, placement),
        firmwareProfile=1 if placement == "body" else 0, tutorialSeconds=0, dataset=ds_id))
dupes = {x for x in ids if ids.count(x) > 1} | {x for x in names if names.count(x) > 1}
assert not dupes, dupes
datasets_used = [EXISTING[e["id"]] for e in current] + [r["dataset"] for r in new_rows]
assert len(set(datasets_used)) == len(datasets_used), "same image twice"
for e in current:
    assert steps(EXISTING[e["id"]]), e["id"]
for r in new_rows:
    assert steps(r["dataset"]), r["id"]

# --- Migration ------------------------------------------------------------------

out = [
    "-- Catálogo ampliado con una selección del dataset abierto",
    "-- https://github.com/hasaneyldrm/exercises-dataset (datos bajo licencia MIT).",
    "-- Nombres traducidos al español; los pasos del tutorial son la traducción",
    "-- al español que trae el dataset. Las miniaturas viven en la app, no aquí.",
    "--",
    "-- firmware_profile: 0 = sensor que rota con un miembro o una barra,",
    "--                   1 = sensor que viaja con el torso (cintura o mochila).",
    "",
    "INSERT INTO exercises",
    "  (id, name, muscle_group, equipment, placement, placement_note, firmware_profile, tutorial_seconds)",
    "VALUES",
]
labels = {"chest": "Pecho", "back": "Espalda", "legs": "Piernas", "shoulders": "Hombros",
          "arms": "Brazos", "core": "Core"}
last_group = None
values = []
for r in new_rows:
    line = ""
    if r["muscleGroup"] != last_group:
        last_group = r["muscleGroup"]
        values.append(f"  -- {labels[last_group]}")
    values.append(
        f"  ({sql(r['id'])}, {sql(r['name'])}, '{r['muscleGroup']}', '{r['equipment']}', "
        f"'{r['placement']}', {sql(r['placementNote'])}, {r['firmwareProfile']}, 0),")
values[-1] = values[-1].rstrip(",") + ";"
out += values
out += [
    "",
    "-- Pasos del tutorial: los ejercicios nuevos y los del catálogo inicial que",
    "-- todavía no tenían (press de banca y flexiones conservan los suyos).",
    "INSERT INTO tutorial_steps (exercise_id, position, body)",
    "VALUES",
]
step_values = []
for e in current:
    if e["id"] in current_steps:
        continue
    for i, s in enumerate(steps(EXISTING[e["id"]]), 1):
        step_values.append(f"  ({sql(e['id'])}, {i}, {sql(s)}),")
for r in new_rows:
    for i, s in enumerate(steps(r["dataset"]), 1):
        step_values.append(f"  ({sql(r['id'])}, {i}, {sql(s)}),")
step_values[-1] = step_values[-1].rstrip(",") + ";"
out += step_values
(API / "db/migrations/003_dataset_exercises.sql").write_text("\n".join(out) + "\n")

# --- App seed (same shape as GET /exercises) -------------------------------------

catalog = []
for e in current:
    catalog.append(dict(
        id=e["id"], name=e["name"], muscleGroup=e["muscleGroup"], equipment=e["equipment"],
        placement=e["placement"], placementNote=e["placementNote"],
        firmwareProfile=e["firmwareProfile"], thresholdDegrees=70,
        tutorialSteps=current_steps.get(e["id"]) or steps(EXISTING[e["id"]]),
        tutorialSeconds=e["tutorialSeconds"], videoUrl=None, active=True))
for r in new_rows:
    catalog.append(dict(
        id=r["id"], name=r["name"], muscleGroup=r["muscleGroup"], equipment=r["equipment"],
        placement=r["placement"], placementNote=r["placementNote"],
        firmwareProfile=r["firmwareProfile"], thresholdDegrees=70,
        tutorialSteps=steps(r["dataset"]), tutorialSeconds=0, videoUrl=None, active=True))
# --- Weight stack (migration 004) ---------------------------------------------------
# 003 stays as it was applied; 004 moves the stack exercises on top of it, and
# the app seed gets the final state.

stack_ids = sorted({e["id"] for e in catalog if e["equipment"] == "cable"} | SELECTOR_MACHINES)
assert SELECTOR_MACHINES <= {e["id"] for e in catalog if e["equipment"] == "machine"}
for e in catalog:
    if e["id"] in stack_ids:
        e.update(placement="equipment", placementNote=STACK_NOTE, firmwareProfile=STACK_PROFILE)

ids_sql = ",\n".join(f"  {sql(i)}" for i in stack_ids)
(API / "db/migrations/004_weight_stack.sql").write_text(f"""-- Ejercicios que levantan una pila de pesas: todos los de polea y las máquinas
-- de selector (la carga se elige con un pasador, sin cambiar discos). El
-- sensor va encima de la pila, pegado a la placa superior, y cuenta con el
-- perfil 2 del firmware, que sigue el movimiento vertical en lugar de la
-- inclinación (la pila sube y baja sin girar).
--
-- Las máquinas de discos (prensa, hack, remo en T, remo alto, Smith, talones)
-- no tienen pila y se quedan como estaban.

UPDATE exercises
   SET placement = 'equipment',
       placement_note = {sql(STACK_NOTE)},
       firmware_profile = {STACK_PROFILE}
 WHERE id IN (
{ids_sql}
);
""")

(IOS / "Catalog").mkdir(parents=True, exist_ok=True)
(IOS / "Catalog" / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=1))

# --- Thumbnails --------------------------------------------------------------------

images = IOS / "ExerciseImages"
if images.exists():
    shutil.rmtree(images)
images.mkdir(parents=True)
mapping = {e["id"]: EXISTING[e["id"]] for e in current} | {r["id"]: r["dataset"] for r in new_rows}
animations = IOS / "ExerciseAnimations"
if animations.exists():
    shutil.rmtree(animations)
animations.mkdir(parents=True)
photos = IOS / "ExercisePhotos"
if photos.exists():
    shutil.rmtree(photos)
photos.mkdir(parents=True)
cache = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "photo-cache"
cache.mkdir(parents=True, exist_ok=True)
assert set(PHOTOS) <= set(mapping), set(PHOTOS) - set(mapping)


def photo(fedb_id, index):
    """A free-exercise-db photo, downloaded once into the cache."""
    path = cache / f"{fedb_id}_{index}.jpg"
    if not path.exists():
        url = f"https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/{fedb_id}/{index}.jpg"
        urllib.request.urlretrieve(url, path)
    return path


for our_id, ds_id in mapping.items():
    shutil.copy(DATASET / dataset[ds_id]["image"], images / f"{our_id}.jpg")
    if our_id in PHOTOS:
        for i in (0, 1):
            # The originals are 850 × 567. 640 px keeps them sharp at the
            # width the app shows them while halving the bundle size.
            with Image.open(photo(PHOTOS[our_id], i)) as im:
                im = im.convert("RGB")
                im.thumbnail((640, 640), Image.LANCZOS)
                im.save(photos / f"{our_id}-{i}.jpg", "JPEG", quality=82, optimize=True, progressive=True)
    else:
        shutil.copy(DATASET / dataset[ds_id]["gif_url"], animations / f"{our_id}.gif")

print(f"actuales: {len(current)}, nuevos: {len(new_rows)}, total: {len(catalog)}, "
      f"pasos: {len(step_values)}, imágenes: {len(mapping)}, con fotos: {len(PHOTOS)}, "
      f"con animación: {len(mapping) - len(PHOTOS)}")
from collections import Counter
print(Counter(e["muscleGroup"] for e in catalog))
print(f"pila de pesas: {len(stack_ids)} ({len(SELECTOR_MACHINES)} máquinas de selector)")
