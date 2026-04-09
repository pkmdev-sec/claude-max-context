#!/bin/bash
_MESH_ADJ=(swift bold calm coral dark deep dusk frost neon noble opal pine scarlet steel vivid warm)
_MESH_ANI=(cobra eagle falcon hornet lemur lynx marten orca osprey puma quail walrus yak zebra)
mesh_random_name() {
  echo "${_MESH_ADJ[$((RANDOM % ${#_MESH_ADJ[@]}))]}-${_MESH_ANI[$((RANDOM % ${#_MESH_ANI[@]}))]}"
}
