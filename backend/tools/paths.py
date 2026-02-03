"""Centralized path resolution for course/hole resources."""

import os

_RESOURCES_ROOT = os.path.join("backend", "resources", "greenMaps")


def course_dir(course_name: str) -> str:
    return os.path.join(_RESOURCES_ROOT, course_name)


def hole_dir(course_name: str, hole_name: str) -> str:
    return os.path.join(_RESOURCES_ROOT, course_name, hole_name)


def config_path(course_name: str, hole_name: str) -> str:
    return os.path.join(hole_dir(course_name, hole_name), "config.json")


def image_path(course_name: str, hole_name: str) -> str:
    return os.path.join(hole_dir(course_name, hole_name), f"{hole_name}.png")


def boundary_path(course_name: str, hole_name: str) -> str:
    return os.path.join(hole_dir(course_name, hole_name), f"{hole_name}_boundary.json")


def contours_path(course_name: str, hole_name: str) -> str:
    return os.path.join(hole_dir(course_name, hole_name), f"{hole_name}_contours.json")


def unity_dir(course_name: str, hole_name: str) -> str:
    return os.path.join(hole_dir(course_name, hole_name), "unity")


def heightfield_bin_path(course_name: str, hole_name: str) -> str:
    return os.path.join(unity_dir(course_name, hole_name), f"{hole_name}_heightfield.bin")


def heightfield_json_path(course_name: str, hole_name: str) -> str:
    return os.path.join(unity_dir(course_name, hole_name), f"{hole_name}_heightfield.json")
