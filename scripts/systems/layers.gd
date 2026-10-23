class_name Layers
## Physics layer bits. Keep these in sync with `project.godot` when layers are
## renamed in the editor.

const WORLD := 1
const PLAYER := 2
const ENEMY := 4
const ENEMY_HIT := 16
## One-way decks. Kept on their own layer so a body can be told to ignore
## them while rising, which is what makes "jump up through the floor" work.
const ONEWAY := 8
