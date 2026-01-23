#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "PyYAML>=6.0",
# ]
# ///
"""
ArgoCD Configuration Renderer

This script renders ArgoCD configurations by:
1. Looping over each folder in argocd/config (each represents a clustertype)
2. Reading config.yaml to get the list of targets (environment, sector, region tuples)
3. For each target, merging application template.yaml files with hierarchical overrides/patches
4. Outputting individual YAML files (one per application) directly to the target folder
"""

import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

import yaml


def load_yaml(file_path: Path) -> Dict[str, Any]:
    """Load and parse a YAML file.

    Args:
        file_path: Path to the YAML file

    Returns:
        Parsed YAML content as a dictionary

    Raises:
        FileNotFoundError: If the file doesn't exist
        yaml.YAMLError: If the file is not valid YAML
    """
    with open(file_path, 'r') as f:
        return yaml.safe_load(f) or {}


def save_yaml(data: Dict[str, Any], file_path: Path) -> None:
    """Save a dictionary as a YAML file.

    Args:
        data: Dictionary to save
        file_path: Path where to save the YAML file
    """
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True, width=float('inf'))


def deep_merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
    """Recursively merge two dictionaries.

    Args:
        base: Base dictionary
        overlay: Dictionary to merge into base

    Returns:
        Merged dictionary
    """
    result = base.copy()

    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value

    return result


def get_clustertypes(config_dir: Path) -> List[str]:
    """Get list of clustertypes from config directory.

    Args:
        config_dir: Path to the config directory

    Returns:
        List of clustertype names (subdirectory names, excluding 'shared')
    """
    return [
        item.name
        for item in config_dir.iterdir()
        if item.is_dir() and not item.name.startswith('.') and item.name != 'shared'
    ]


def get_targets(config_file: Path) -> List[Tuple[str, str, str]]:
    """Parse config.yaml to extract targets.

    Args:
        config_file: Path to config.yaml

    Returns:
        List of (environment, sector, region) tuples
    """
    config = load_yaml(config_file)
    targets = []

    for target in config.get('targets', []):
        environment = target.get('environment')
        sector = target.get('sector')
        region = target.get('region')

        if environment and sector and region:
            targets.append((environment, sector, region))
        else:
            print(f"Warning: Skipping incomplete target: {target}", file=sys.stderr)

    return targets


def get_application_folders(clustertype_dir: Path) -> List[Path]:
    """Get all application folders within a clustertype directory.

    Args:
        clustertype_dir: Path to the clustertype directory

    Returns:
        List of paths to application folders (those containing template.yaml)
    """
    applications = []

    for item in clustertype_dir.iterdir():
        if item.is_dir() and not item.name.startswith('.'):
            template_file = item / 'template.yaml'
            if template_file.exists():
                applications.append(item)

    return applications


def get_all_application_folders(clustertype_dir: Path, shared_dir: Path) -> List[Path]:
    """Get all application folders including both cluster-specific and shared applications.

    Args:
        clustertype_dir: Path to the clustertype directory
        shared_dir: Path to the shared directory

    Returns:
        List of paths to application folders (shared applications first, then cluster-specific)
    """
    applications = []

    # First add shared applications (if shared directory exists)
    if shared_dir.exists():
        applications.extend(get_application_folders(shared_dir))

    # Then add cluster-specific applications
    applications.extend(get_application_folders(clustertype_dir))

    return applications


def get_application_manifest(
    app_folder: Path,
    environment: str,
    sector: str,
    region: str
) -> Dict[str, Any]:
    """Get merged manifest for an application with overrides and patches.

    Merges in this order:
    1. Base template.yaml
    2. For each matching path (environment, environment/sector, environment/sector/region):
       - override.yaml (if exists)
       - patch-*.yaml files in alphabetical order

    Args:
        app_folder: Path to the application folder
        environment: Target environment
        sector: Target sector
        region: Target region

    Returns:
        Merged manifest dictionary
    """
    # Start with base template
    base_template_file = app_folder / 'template.yaml'
    merged = load_yaml(base_template_file)

    # Define possible override paths in order of specificity
    override_paths = [
        app_folder / environment,
        app_folder / environment / sector,
        app_folder / environment / sector / region,
    ]

    # Merge override.yaml and patch-*.yaml files
    for path in override_paths:
        if path.exists() and path.is_dir():
            # First, merge override.yaml if it exists
            override_file = path / 'override.yaml'
            if override_file.exists():
                override_data = load_yaml(override_file)
                merged = deep_merge(merged, override_data)

            # Then, merge patch-*.yaml files in alphabetical order
            patch_files = sorted(path.glob('patch-*.yaml'))
            for patch_file in patch_files:
                patch_data = load_yaml(patch_file)
                merged = deep_merge(merged, patch_data)

    return merged


def merge_values_with_shared(
    clustertype: str,
    config_dir: Path
) -> Dict[str, Any]:
    """Merge cluster-specific values with shared values.

    Shared values are used as defaults when they don't exist in cluster values.
    Cluster-specific values take priority over shared values.

    Args:
        clustertype: Name of the clustertype
        config_dir: Path to the config directory

    Returns:
        Merged values dictionary
    """
    # Load shared values as defaults
    shared_values_file = config_dir / 'shared' / 'values.yaml'
    shared_values = {}
    if shared_values_file.exists():
        shared_values = load_yaml(shared_values_file)

    # Load cluster-specific values
    cluster_values_file = config_dir / clustertype / 'values.yaml'
    cluster_values = {}
    if cluster_values_file.exists():
        cluster_values = load_yaml(cluster_values_file)

    # Merge with cluster values taking priority
    merged_values = deep_merge(shared_values, cluster_values)

    return merged_values


def render_clustertype(
    clustertype: str,
    config_dir: Path,
    rendered_dir: Path
) -> None:
    """Render configurations for a specific clustertype.

    Args:
        clustertype: Name of the clustertype
        config_dir: Path to the config directory
        rendered_dir: Path to the rendered output directory
    """
    clustertype_dir = config_dir / clustertype
    config_file = clustertype_dir / 'config.yaml'
    values_file_source = clustertype_dir / 'values.yaml'

    if not config_file.exists():
        print(f"Error: No config.yaml found for clustertype '{clustertype}'", file=sys.stderr)
        return

    if not values_file_source.exists():
        print(f"Error: No values.yaml found for clustertype '{clustertype}'", file=sys.stderr)
        return

    # Get targets from config.yaml
    targets = get_targets(config_file)

    if not targets:
        print(f"Warning: No targets found for clustertype '{clustertype}', skipping", file=sys.stderr)
        return

    # Get application folders (including shared applications)
    shared_dir = config_dir / 'shared'
    application_folders = get_all_application_folders(clustertype_dir, shared_dir)

    if not application_folders:
        print(f"Warning: No application folders found for clustertype '{clustertype}', skipping", file=sys.stderr)
        return

    # Process each target
    for environment, sector, region in targets:
        print(f"Processing {clustertype}/{environment}/{sector}/{region}")

        # Create base output directory for the Helm chart
        chart_dir = rendered_dir / clustertype / environment / sector / region
        chart_dir.mkdir(parents=True, exist_ok=True)

        # Create Chart.yaml
        chart_name = f"{clustertype}-{environment}-{sector}-{region}"
        chart_data = {
            'apiVersion': 'v2',
            'name': chart_name,
            'description': f'ArgoCD applications for {clustertype} cluster in {environment}/{sector}/{region}',
            'type': 'application',
            'version': '0.1.0',
        }
        chart_file = chart_dir / 'Chart.yaml'
        save_yaml(chart_data, chart_file)
        print(f"  [OK] {chart_file.relative_to(rendered_dir.parent)}")

        # Merge cluster values with shared values and save
        values_file = chart_dir / 'values.yaml'
        merged_values = merge_values_with_shared(clustertype, config_dir)
        save_yaml(merged_values, values_file)
        print(f"  [OK] {values_file.relative_to(rendered_dir.parent)}")

        # Create templates directory
        templates_dir = chart_dir / 'templates'
        templates_dir.mkdir(exist_ok=True)

        # Process each application individually
        for app_folder in application_folders:
            app_name = app_folder.name
            app_manifest = get_application_manifest(app_folder, environment, sector, region)

            # Save individual application file in templates/
            output_file = templates_dir / f'{app_name}.yaml'
            save_yaml(app_manifest, output_file)
            print(f"  [OK] {output_file.relative_to(rendered_dir.parent)}")


def main() -> int:
    """Main entry point for the script.

    Returns:
        Exit code (0 for success, 1 for error)
    """
    # Determine script location and project root
    script_dir = Path(__file__).parent
    project_root = script_dir.parent.parent

    config_dir = project_root / 'argocd' / 'config'
    rendered_dir = project_root / 'argocd' / 'rendered'

    if not config_dir.exists():
        print(f"Error: Config directory not found: {config_dir}", file=sys.stderr)
        return 1

    # Get all clustertypes
    clustertypes = get_clustertypes(config_dir)

    if not clustertypes:
        print(f"Error: No clustertypes found in {config_dir}", file=sys.stderr)
        return 1

    print(f"Found clustertypes: {', '.join(clustertypes)}")
    print()

    # Process each clustertype
    for clustertype in clustertypes:
        render_clustertype(clustertype, config_dir, rendered_dir)
        print()

    print("[OK] Rendering complete")
    return 0


if __name__ == '__main__':
    sys.exit(main())