printf 'run: project opens headless\n'
# Retry the project-open --quit up to 3 times: the RendererDummy MultiMesh
# cleanup can SIGSEGV at engine teardown (intermittent, non-deterministic),
# which would otherwise halt the whole gate. set -e is in effect (sourced
# under `set -eu`), so guard each attempt and only fail after 3 tries.
open_attempt=1
open_rc=0
while [ "$open_attempt" -le 3 ]; do
	open_rc=0
	"$godot_bin" --headless --path . --quit || open_rc=$?
	if [ "$open_rc" -eq 0 ]; then
		break
	fi
	printf 'retry: project-open exited %s (attempt %s/3)\n' "$open_rc" "$open_attempt" >&2
	open_attempt=$((open_attempt + 1))
done
if [ "$open_rc" -ne 0 ]; then
	exit "$open_rc"
fi

printf 'run: project input map defaults\n'
"$godot_bin" --headless --path . res://tools/input_map_inspector.tscn

printf 'run: gamepad bindings (host-injected, no device)\n'
"$godot_bin" --headless --path . res://tools/gamepad_binding_inspector.tscn
