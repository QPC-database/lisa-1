"""Provides and parameterizes the `pool` and `target` fixtures.

TODO
====
* Provide a `targets` fixture for tests which use more than one target
  at a time.
* Deallocate targets when switching to a new target.
* Use richer feature/requirements comparison for targets.
* Add `pytest.mark.target` instead of LISA mark for target
  requirements.
* Reimplement caching of targets between runs.
* Improve schema with annotations, error messages, etc.

"""
from __future__ import annotations

import typing
from uuid import uuid4

import playbook
import pytest

# See https://pypi.org/project/schema/
from schema import Literal, Optional, Or, Schema  # type: ignore
from target.target import SSH, Target

if typing.TYPE_CHECKING:
    from typing import Any, Dict, Iterator, List, Set, Type

    from _pytest.config.argparsing import Parser
    from _pytest.fixtures import SubRequest
    from _pytest.python import Metafunc


def pytest_addoption(parser: Parser) -> None:
    """Pytest hook to add our CLI options."""
    group = parser.getgroup("target")
    group.addoption("--keep-vms", action="store_true", help="Keeps deployed VMs.")


platforms: Dict[str, Type[Target]] = dict()


def pytest_playbook_schema(schema: Dict[Any, Any]) -> None:
    """pytest-playbook hook to update the playbook schema.

    The `platforms` global is a mapping of platform names (strings) to
    the implementing subclasses of `Target` where each subclass
    defines its own parameters `schema`, `deploy` and `delete`
    methods, and other platform-specific functionality. A `Target`
    subclass need only be defined in a file loaded by Pytest, so a
    `conftest.py` file works just fine.

    TODO: Add field annotations, friendly error reporting, automatic
    case transformations, etc.

    """
    global platforms
    platforms = {cls.__name__: cls for cls in Target.__subclasses__()}  # type: ignore
    target_schema = Or(
        # We’re unpacking a list of updated schema from each platform.
        *(
            {
                # We’re adding ‘name’ and ‘platform’ keys to each
                # platform’s schema.
                Literal("name", description="A friendly name for the target."): str,
                Literal(
                    "platform",
                    description="The literal class name of the platform implementation,"
                    + " a subclass of `Target`.",
                ): name,
                **cls.schema(),
            }
            for name, cls in platforms.items()
        )
    )
    default_targets = [
        {"name": "Default", "platform": "SSH", **Schema(SSH.schema()).validate({})}
    ]
    schema[Optional("targets", default=default_targets)] = [target_schema]


@pytest.fixture(scope="session")
def pool(request: SubRequest) -> Iterator[List[Target]]:
    """This fixture tracks all deployed target resources."""
    targets: List[Target] = []
    yield targets
    for t in targets:
        # TODO: Use proper logging?
        print(f"Created target: {t.features} / {t.params}")
        if not request.config.getoption("keep_vms"):
            t.delete()


def get_target(
    pool: List[Target],
    request: SubRequest,
) -> Target:
    """This function gets or creates an appropriate `Target`.

    First check if any existing target in the `pool` matches all the
    `features` and other requirements. If so, we can re-use that
    target, and if not, we can deallocate the currently running target
    and allocate a new one. When all tests are finished, the pool
    fixture above will delete all created VMs. We can achieve
    two-layer scheduling by implementing a custom scheduler in
    pytest-xdist via `pytest_xdist_make_scheduler` and sorting the
    tests such that they're grouped by features.

    """
    # Unpack the request.
    params: Dict[str, Any] = request.param
    platform: Type[Target] = platforms[params["platform"]]
    # TODO: Use a ‘target’ marker instead.
    marker = request.node.get_closest_marker("lisa")
    features: Set[str] = set(marker.kwargs["features"])

    # TODO: If `t` is not already in use, deallocate the previous
    # target, and ensure the tests have been sorted (and so grouped)
    # by their requirements.
    for t in pool:
        # TODO: Implement full feature comparison, etc. and not just
        # proof-of-concept string set comparison.
        if isinstance(t, platform) and t.params == params and t.features >= features:
            pool.remove(t)
            return t
    else:
        # TODO: Reimplement caching.
        t = platform(f"pytest-{uuid4()}", params, features)
        return t


def cleanup_target(pool: List[Target], t: Target) -> None:
    """This is called by fixtures after they're done with a target."""
    t.conn.close()
    pool.append(t)


@pytest.fixture
def target(pool: List[Target], request: SubRequest) -> Iterator[Target]:
    """This fixture provides a connected target for each test.

    It is parametrized indirectly in `pytest_generate_tests`.

    """
    t = get_target(pool, request)
    yield t
    cleanup_target(pool, t)


@pytest.fixture(scope="class")
def c_target(pool: List[Target], request: SubRequest) -> Iterator[Target]:
    """This fixture is the same as `target` but shared across a class."""
    t = get_target(pool, request)
    yield t
    cleanup_target(pool, t)


@pytest.fixture(scope="module")
def m_target(pool: List[Target], request: SubRequest) -> Iterator[Target]:
    """This fixture is the same as `target` but shared across a module."""
    t = get_target(pool, request)
    yield t
    cleanup_target(pool, t)


targets: List[Dict[str, Any]] = []
target_ids: List[str] = []


def pytest_sessionstart() -> None:
    """Gather the `targets` from the playbook."""
    for target in playbook.data.get("targets", []):
        targets.append(target)
        target_ids.append("Target=" + target["name"])


def pytest_generate_tests(metafunc: Metafunc) -> None:
    """Indirectly parametrize the `target` fixture based on the playbook.

    This hook is run for each test, so we gather the `targets` in
    `pytest_sessionstart`.

    TODO: Handle `targets` being empty (probably a user-error). Also
    consider how this may change if we want to selectively
    parameterize tests.

    """
    if "target" in metafunc.fixturenames:
        metafunc.parametrize("target", targets, True, target_ids)
    if "m_target" in metafunc.fixturenames:
        metafunc.parametrize("m_target", targets, True, target_ids)
    if "c_target" in metafunc.fixturenames:
        metafunc.parametrize("c_target", targets, True, target_ids)