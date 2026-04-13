"""
GLB/glTF validation script.
Checks for duplicate names and animation target issues.

Usage:
    python validate_glb.py <path_to_glb>
"""

import json
import struct
import sys
from collections import Counter
from typing import Any


def load_glb(path: str) -> dict[str, Any]:
    with open(path, "rb") as f:
        magic, version, length = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:
            raise ValueError(f"Not a valid GLB file (magic: {magic:#x})")
        chunk_len, chunk_type = struct.unpack("<II", f.read(8))
        if chunk_type != 0x4E4F534A:
            raise ValueError("First chunk is not JSON")
        return json.loads(f.read(chunk_len))


def check_duplicate_names(items: list[dict], label: str, errors: list[str]) -> None:
    names: list[str] = [item.get("name", "") for item in items]
    counts: Counter[str] = Counter(names)
    for name, count in counts.items():
        if count > 1 and name:
            errors.append(f"Duplicate {label} name: \"{name}\" appears {count} times")


def build_node_ancestry(gltf: dict[str, Any]) -> dict[int, int]:
    """Returns child_index -> parent_index mapping."""
    parent_map: dict[int, int] = {}
    for i, node in enumerate(gltf.get("nodes", [])):
        for child in node.get("children", []):
            parent_map[child] = i
    return parent_map


def find_armature_for_node(
    node_idx: int,
    parent_map: dict[int, int],
    skin_roots: dict[int, int],
    skin_joints: dict[int, int],
    nodes: list[dict],
) -> str | None:
    """Walk up from node_idx to find which skin/armature it belongs to."""
    # Check if node is a joint in a skin
    if node_idx in skin_joints:
        skin_idx: int = skin_joints[node_idx]
        skin: dict = nodes[skin_idx] if skin_idx < len(nodes) else {}
        return skin.get("name", f"skin_{skin_idx}")

    # Walk up parents to find a node that is a skin root
    visited: set[int] = set()
    current: int = node_idx
    while current in parent_map and current not in visited:
        visited.add(current)
        current = parent_map[current]
        if current in skin_roots:
            return nodes[current].get("name", f"node_{current}")
    return None


def validate_glb(path: str) -> list[str]:
    gltf: dict[str, Any] = load_glb(path)
    errors: list[str] = []
    nodes: list[dict] = gltf.get("nodes", [])
    meshes: list[dict] = gltf.get("meshes", [])
    animations: list[dict] = gltf.get("animations", [])
    skins: list[dict] = gltf.get("skins", [])
    accessors: list[dict] = gltf.get("accessors", [])

    # --- 1. Duplicate top-level names ---
    check_duplicate_names(nodes, "node", errors)
    check_duplicate_names(meshes, "mesh", errors)
    check_duplicate_names(animations, "animation", errors)
    check_duplicate_names(skins, "skin", errors)

    # --- 2. Duplicate bone names within each skin ---
    for si, skin in enumerate(skins):
        skin_name: str = skin.get("name", f"skin_{si}")
        joint_indices: list[int] = skin.get("joints", [])
        bone_names: list[str] = []
        for ji in joint_indices:
            if ji < len(nodes):
                bone_names.append(nodes[ji].get("name", f"node_{ji}"))
            else:
                errors.append(
                    f"Skin \"{skin_name}\": joint index {ji} out of range "
                    f"(only {len(nodes)} nodes)"
                )
        counts: Counter[str] = Counter(bone_names)
        for name, count in counts.items():
            if count > 1:
                errors.append(
                    f"Skin \"{skin_name}\": duplicate bone name \"{name}\" "
                    f"appears {count} times"
                )

    # --- 3. Build skin membership maps ---
    parent_map: dict[int, int] = build_node_ancestry(gltf)

    # Map: joint node index -> skin index
    joint_to_skin: dict[int, int] = {}
    for si, skin in enumerate(skins):
        for ji in skin.get("joints", []):
            joint_to_skin[ji] = si

    # Map: skin root node index -> skin index
    skin_root_nodes: dict[int, int] = {}
    for si, skin in enumerate(skins):
        skeleton: int | None = skin.get("skeleton")
        if skeleton is not None:
            skin_root_nodes[skeleton] = si

    # --- 4. Animation channel validation ---
    for ai, anim in enumerate(animations):
        anim_name: str = anim.get("name", f"animation_{ai}")
        channels: list[dict] = anim.get("channels", [])
        samplers: list[dict] = anim.get("samplers", [])
        targeted_skins: set[int] = set()

        for ci, channel in enumerate(channels):
            target: dict = channel.get("target", {})
            node_idx: int | None = target.get("node")
            path: str = target.get("path", "?")

            # Check node exists
            if node_idx is None:
                errors.append(
                    f"Animation \"{anim_name}\" channel {ci}: "
                    f"missing target node"
                )
                continue
            if node_idx >= len(nodes):
                errors.append(
                    f"Animation \"{anim_name}\" channel {ci}: "
                    f"target node {node_idx} out of range (only {len(nodes)} nodes)"
                )
                continue

            node_name: str = nodes[node_idx].get("name", f"node_{node_idx}")

            # Check valid path
            valid_paths: list[str] = [
                "translation", "rotation", "scale", "weights",
            ]
            if path not in valid_paths:
                errors.append(
                    f"Animation \"{anim_name}\" channel {ci}: "
                    f"invalid path \"{path}\" on node \"{node_name}\""
                )

            # Check sampler exists
            sampler_idx: int | None = channel.get("sampler")
            if sampler_idx is not None and sampler_idx >= len(samplers):
                errors.append(
                    f"Animation \"{anim_name}\" channel {ci}: "
                    f"sampler index {sampler_idx} out of range"
                )

            # Check sampler accessor bounds
            if sampler_idx is not None and sampler_idx < len(samplers):
                sampler: dict = samplers[sampler_idx]
                for key in ["input", "output"]:
                    acc_idx: int | None = sampler.get(key)
                    if acc_idx is not None and acc_idx >= len(accessors):
                        errors.append(
                            f"Animation \"{anim_name}\" channel {ci}: "
                            f"sampler {key} accessor {acc_idx} out of range"
                        )

            # Track which skin this channel targets
            if node_idx in joint_to_skin:
                targeted_skins.add(joint_to_skin[node_idx])

        # Warn if a single animation targets multiple skins
        if len(targeted_skins) > 1:
            skin_names: list[str] = []
            for si in sorted(targeted_skins):
                skin_names.append(skins[si].get("name", f"skin_{si}"))
            errors.append(
                f"Animation \"{anim_name}\" targets bones from "
                f"{len(targeted_skins)} different skins: "
                f"{', '.join(skin_names)}"
            )

    # --- 5. Accessor sharing between animations ---
    warnings: list[str] = []
    anim_accessor_use: dict[int, list[str]] = {}
    for ai, anim in enumerate(animations):
        anim_name = anim.get("name", f"animation_{ai}")
        for sampler in anim.get("samplers", []):
            for key in ["input", "output"]:
                acc_idx = sampler.get(key)
                if acc_idx is not None:
                    if acc_idx not in anim_accessor_use:
                        anim_accessor_use[acc_idx] = []
                    anim_accessor_use[acc_idx].append(anim_name)

    shared_accessor_count: int = 0
    shared_accessor_groups: dict[str, int] = {}
    for acc_idx, users in anim_accessor_use.items():
        unique_users: list[str] = sorted(set(users))
        if len(unique_users) > 1:
            shared_accessor_count += 1
            group_key: str = ", ".join(unique_users)
            shared_accessor_groups[group_key] = (
                shared_accessor_groups.get(group_key, 0) + 1
            )

    if shared_accessor_count > 0:
        warnings.append(
            f"{shared_accessor_count} accessor(s) shared between animations "
            f"(may cause import issues in some engines):"
        )
        for group, count in shared_accessor_groups.items():
            warnings.append(f"  {count} accessor(s) shared by: {group}")

    # --- 6. Check for duplicate channels (same node + same path) per animation ---
    for ai, anim in enumerate(animations):
        anim_name = anim.get("name", f"animation_{ai}")
        seen_targets: set[tuple[int, str]] = set()
        for ci, channel in enumerate(anim.get("channels", [])):
            target = channel.get("target", {})
            node_idx = target.get("node")
            path = target.get("path", "")
            if node_idx is not None:
                key: tuple[int, str] = (node_idx, path)
                if key in seen_targets:
                    node_name = nodes[node_idx].get("name", f"node_{node_idx}")
                    errors.append(
                        f"Animation \"{anim_name}\": duplicate channel for "
                        f"node \"{node_name}\" path \"{path}\""
                    )
                seen_targets.add(key)

    return errors, warnings


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: python {sys.argv[0]} <file.glb>")
        sys.exit(1)

    path: str = sys.argv[1]
    print(f"Validating: {path}\n")

    errors, warnings = validate_glb(path)

    if warnings:
        print(f"Warnings ({len(warnings)}):\n")
        for w in warnings:
            print(f"  {w}")
        print()

    if not errors:
        print("OK - No errors found.")
    else:
        print(f"Found {len(errors)} error(s):\n")
        for i, err in enumerate(errors, 1):
            print(f"  [{i}] {err}")
        sys.exit(1)


if __name__ == "__main__":
    main()
